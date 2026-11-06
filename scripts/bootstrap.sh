#!/usr/bin/env bash
# ONE-TIME account bootstrap - run from your laptop with ADMIN credentials.
# Creates the shared stack: ECR repos, artifact bucket, CloudFormation execution
# role, least-privilege deploy policies and the GitHub OIDC roles.
# Usage: bootstrap.sh <github-owner> <github-repo> [create-oidc-provider:true|false]
source "$(dirname "$0")/lib.sh"
OWNER="${1:?usage: bootstrap.sh <github-owner> <github-repo> [true|false]}"
REPO="${2:?usage: bootstrap.sh <github-owner> <github-repo> [true|false]}"
OIDC="${3:-}"
if [[ -z "$OIDC" ]]; then
  if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text \
       | grep -q token.actions.githubusercontent.com; then OIDC=false; else OIDC=true; fi
fi
log "Deploying ${PROJECT_NAME}-shared in ${AWS_REGION} (account $(account_id), create OIDC provider: $OIDC)"
aws cloudformation deploy --stack-name "${PROJECT_NAME}-shared" \
  --template-file "$REPO_ROOT/infra/cloudformation/shared.yaml" \
  --parameter-overrides ProjectName="$PROJECT_NAME" GitHubOrg="$OWNER" GitHubRepo="$REPO" CreateGitHubOidcProvider="$OIDC" \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags "Project=${PROJECT_NAME}" "ManagedBy=CloudFormation" \
  --no-fail-on-empty-changeset
echo
ok "Shared stack ready. Configure these GitHub repository VARIABLES (Settings > Secrets and variables > Actions > Variables):"
echo "  AWS_REGION                = $AWS_REGION"
echo "  PROJECT_NAME              = $PROJECT_NAME"
echo "  AWS_APP_DEPLOY_ROLE_ARN   = $(stack_output "${PROJECT_NAME}-shared" GitHubAppDeployRoleArn)"
echo "  AWS_INFRA_DEPLOY_ROLE_ARN = $(stack_output "${PROJECT_NAME}-shared" GitHubInfraDeployRoleArn)"
echo "  CD_PROVIDER               = github   (or 'aws' if you deploy pipelines.yaml)"
