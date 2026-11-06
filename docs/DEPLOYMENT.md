# Deployment Guide (step by step)

This guide takes a brand-new AWS account to a running **dev** environment. Both deployment approaches are covered: containerized on ECS and non-containerized on EC2 with CodeDeploy. Staging and prod work the same way.

> Region used in the examples: **ap-south-1 (Mumbai)**. You can use any region; just set `AWS_REGION` everywhere.

---

## 0. Prerequisites

| Tool | Needed for | Notes |
|---|---|---|
| AWS account + an IAM user/role with **AdministratorAccess** | the one-time bootstrap only | After bootstrap, pipelines use their own least-privilege roles |
| AWS CLI v2, `git`, `jq`, `bash` | running the scripts | On Windows use **WSL2** or Git Bash. **AWS CloudShell** already has all of these (bootstrap and infra only; it cannot build images) |
| GitHub account | the repo and GitHub Actions | |
| Docker + Node 22 + Python 3.12 | **only** if you build from your laptop (Path B) | Not needed with Path A, where GitHub Actions builds everything |

Set up your shell once:

```bash
aws configure                  # or: aws sso login / export AWS_PROFILE=...
export AWS_REGION=ap-south-1
export PROJECT_NAME=r2app      # keep the default unless you have a reason to change it
aws sts get-caller-identity    # confirm the right account
```

**Before you start, create a budget alert:** Billing → Budgets → Create budget → "Zero spend budget" or a monthly cost budget of USD 5.

---

## 1. Put the code on GitHub

```bash
unzip r2-devops-assessment.zip && cd r2-devops-assessment
git init -b main && git add . && git commit -m "Initial commit"
gh repo create <your-user>/r2-devops-assessment --private --source . --push
# or create an empty repo on github.com and:
# git remote add origin https://github.com/<you>/r2-devops-assessment.git && git push -u origin main
```

> The first push starts the GitHub workflows. They fail harmlessly until step 3 is done.

---

## 2. Bootstrap the account (one time, admin credentials)

```bash
bash scripts/bootstrap.sh <github-owner> r2-devops-assessment
```

This creates the **`r2app-shared`** stack:
* the ECR repos `r2app/frontend` and `r2app/backend`
* the S3 artifact bucket
* the CloudFormation execution role
* the `app-deploy` and `infra-deploy` policies
* the GitHub OIDC provider and the two GitHub roles

At the end the script prints the values you need in step 3.

---

## 3. Configure GitHub

**Settings → Secrets and variables → Actions → Variables tab → New repository variable.** These are variables, not secrets. Nothing secret is stored in GitHub.

| Variable | Value |
|---|---|
| `AWS_REGION` | `ap-south-1` |
| `PROJECT_NAME` | `r2app` |
| `AWS_APP_DEPLOY_ROLE_ARN` | printed by bootstrap |
| `AWS_INFRA_DEPLOY_ROLE_ARN` | printed by bootstrap |
| `CD_PROVIDER` | `github` (use `aws` only if you set up section 7) |
| `ENABLED_ENVIRONMENTS` | `dev` (later `dev,staging,prod`) |

**Settings → Environments:** create `dev`, `staging` and `prod`. On `staging` and `prod`, tick **Required reviewers** and add yourself. These are the approval gates.

---

## 4. First deployment of dev

Order matters the first time, because the ECS stack needs an image to exist. Choose one path.

### Path A: everything from GitHub Actions (recommended, no local Docker)

1. **Actions → App deploy → Run workflow** (branch `main`).
   This tests and builds the images and the EC2 bundle. The `deploy-dev` job then reports that the stacks don't exist yet, skips them, and records the release tag in SSM.
2. **Actions → Infra deploy → Run workflow.**
   This creates the 7 dev stacks: network, security, alb, database, monitoring, ecs and ec2. **Expect 15–25 minutes**, mostly RDS. ECS starts directly on the release from step 1.
3. **Actions → App deploy → Run workflow** again.
   CodeDeploy now ships the release to the EC2 instance, and ECS confirms the same release.

### Path B: from your laptop (Docker required)

```bash
bash scripts/first-deploy.sh dev      # = build-and-push → deploy-infra dev apply → deploy-app dev
```

### Open the apps

The last lines of the infra job (or `first-deploy.sh`) print both URLs:

```
ecs URL: http://r2app-dev-alb-123456.ap-south-1.elb.amazonaws.com:80
ec2 URL: http://r2app-dev-alb-123456.ap-south-1.elb.amazonaws.com:8080
```

Each page shows the environment, **where it runs** ("ECS (container)" or "EC2 (no container)"), the release SHA, and whether the database is **connected**. Add an item: it is written to PostgreSQL, and you can read it back from either URL because both use the same database.

Quick checks:
```bash
ALB=$(aws cloudformation describe-stacks --stack-name r2app-dev-alb --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDnsName'].OutputValue" --output text)
curl http://$ALB/api/info         # containerized backend
curl http://$ALB:8080/api/info    # non-containerized backend
curl http://$ALB/api/ready        # includes the DB check
```

---

## 5. Day-2 operations

### Ship an application change
Edit anything under `apps/`, then commit and push to `main`. **Only** the *App deploy* workflow runs: test → build once → dev → (approval) staging → (approval) prod. CloudFormation is never touched.

### Ship an infrastructure change
Edit a template in `infra/cloudformation/` or a value in `infra/environments/<env>.json`, then push. **Only** *Infra deploy* runs. Read the **change-set plan** in the job summary before you approve staging or prod.

Locally:
```bash
bash scripts/deploy-infra.sh dev plan          # what would change
bash scripts/deploy-infra.sh dev apply         # all stacks in order
bash scripts/deploy-infra.sh dev apply ecs     # a single stack
```

### Roll back the application
* **Automatic:** an ECS circuit breaker or CodeDeploy auto-rollback runs on any failed health check, failed hook or 5xx alarm.
* **Manual:** *Actions → App rollback → Run workflow*. Choose the environment and leave the tag empty to go back to the previous release, or enter any earlier commit SHA.
  ```bash
  bash scripts/rollback-app.sh dev            # previous release
  bash scripts/rollback-app.sh dev 1a2b3c...  # a specific release
  ```

### Roll back infrastructure
A failed stack update rolls itself back. To undo a *successful* change, `git revert` the commit and push.

### See logs and metrics
* CloudWatch → Log groups → `/r2app/dev/ecs/*` and `/r2app/dev/ec2/*`
* CloudWatch → Dashboards → `r2app-dev`
* Shell on an instance (no SSH): EC2 → instance → **Connect → Session Manager**
* To receive alarm e-mails, set `"AlertEmail"` in `infra/environments/dev.json` (monitoring section), push, and confirm the subscription e-mail.

### Turn on HTTPS
Request an ACM certificate for your domain in the same region and validate it. Set `CertificateArn` in the `ecs` and `ec2` sections of the environment file, then point a CNAME or Route 53 alias at the ALB. HTTP then redirects to HTTPS: port 443 for ECS, 8443 for EC2.

---

## 6. Staging and production

1. Set `ENABLED_ENVIRONMENTS` to `dev,staging,prod`.
2. Run *Infra deploy*. After dev, approve the staging and prod jobs. **These environments cost money** (NAT gateways, Multi-AZ RDS, WAF, more instances).
3. The next *App deploy* promotes the same release through every environment, with approvals.

---

## 7. Optional: AWS-native CD (CodePipeline + CodeBuild + CodeDeploy)

```bash
aws cloudformation deploy --stack-name r2app-pipelines \
  --template-file infra/cloudformation/pipelines.yaml \
  --parameter-overrides ProjectName=r2app GitHubOwner=<owner> GitHubRepo=r2-devops-assessment \
  --capabilities CAPABILITY_IAM
```

1. Console → **Developer Tools → Settings → Connections** → `r2app-github` → **Update pending connection** → authorize the GitHub app for your repo. The status must become **Available**.
2. Set the GitHub variable `CD_PROVIDER=aws`. GitHub keeps running tests, and CodePipeline now does the deployments.
3. Push a change under `apps/**`: only **`r2app-app`** runs. Push a change under `infra/**`: only **`r2app-infra`** runs. Approve stages in the CodePipeline console.

---

## 8. Tear down (stop all charges)

```bash
bash scripts/destroy.sh dev            # deletes the 7 env stacks in reverse order
aws cloudformation delete-stack --stack-name r2app-pipelines   # if created
aws cloudformation delete-stack --stack-name r2app-shared      # ECR repos are emptied automatically
```

Then clean up two things that are kept on purpose:
* RDS → **Snapshots**: delete `r2app-dev-postgres-snapshot-*` (the final snapshot).
* S3: empty and delete the bucket `r2app-artifacts-<account>-<region>`.

---

## 9. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` in GitHub | Wrong owner or repo name passed to bootstrap, or the workflow ran on a branch other than `main`. Re-run bootstrap with the exact owner and repo. |
| Bootstrap fails with `EntityAlreadyExists` for the OIDC provider | The account already has one. Run `bash scripts/bootstrap.sh <owner> <repo> false`. |
| `backup retention period exceeds the maximum available to free tier` | Keep `BackupRetentionDays` at `1` in `dev.json` (the default). |
| `instance type is not eligible for Free Tier` / account-plan errors | Check *EC2 → Instance types → Free tier eligible* and set `InstanceType` (for example `t2.micro` or `t4g.micro`, though `t4g` also needs ARM AMIs) or `DbInstanceClass`. Free-plan accounts may need to upgrade to the Paid plan (credits still apply). |
| ECS stack skipped: *no application image in ECR yet* | Run *App deploy* (or `build-and-push.sh`) first, then infra again. |
| `r2app-dev-ec2` stuck in CREATE, then fails on the CreationPolicy | The instance could not bootstrap. Connect with Session Manager and read `/var/log/user-data.log`. Usually there is no outbound internet: check `NatGatewayMode` or the public IP. |
| CodeDeploy deployment failed | CodeDeploy console → deployment → instance → event log. Agent log: `/var/log/aws/codedeploy-agent/codedeploy-agent.log`. App logs: CloudWatch `/r2app/dev/ec2/*`. |
| ECS tasks keep restarting | CloudWatch `/r2app/dev/ecs/backend`. ECS console → service → *Deployments and events*. |
| Page loads but "Database: unavailable" | Check the DB security group, and that the secret ARN is readable by the task or instance role. Read `/api/ready` and the backend logs. |
| `aws cloudformation deploy` says *No changes to deploy* | Expected. The script continues (`--no-fail-on-empty-changeset`). |
