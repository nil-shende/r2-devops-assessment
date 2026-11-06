#!/usr/bin/env bash
# INFRASTRUCTURE deployment for one environment (never builds or ships app code).
#   plan  : creates a CloudFormation change set per stack, prints it, deletes it
#   apply : deploys the stacks in dependency order via change sets
# Parameters come from infra/environments/<env>.json (one section per stack),
# so dev / staging / prod differ ONLY in configuration, never in templates.
# Usage: deploy-infra.sh <env> [plan|apply] [stack ...]
source "$(dirname "$0")/lib.sh"
ENV="${1:-}"; MODE="${2:-apply}"; shift 2 2>/dev/null || shift $#
validate_env "$ENV"
[[ "$MODE" == plan || "$MODE" == apply ]] || die "mode must be plan or apply"
require aws jq

ORDER=(network security alb database monitoring ecs ec2)
if [[ $# -gt 0 ]]; then STACKS=("$@"); else STACKS=("${ORDER[@]}"); fi
CONFIG="$REPO_ROOT/infra/environments/${ENV}.json"
[[ -f "$CONFIG" ]] || die "missing $CONFIG"
BUCKET="$(artifacts_bucket)"
EXEC_ROLE="arn:aws:iam::$(account_id):role/${PROJECT_NAME}-cfn-execution-role"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# "Key=Value" pairs for one stack: common params + its section of the env file
params_for() {
  local comp=$1
  echo "ProjectName=${PROJECT_NAME}"
  echo "EnvironmentName=${ENV}"
  jq -r --arg c "$comp" '(.[$c] // {}) | to_entries[] | "\(.key)=\(.value)"' "$CONFIG"
  if [[ "$comp" == ecs ]]; then echo "ImageTag=$(release_param "$ENV" image-tag)"; fi
}

# The ECS stack needs a released image tag in SSM. On the very first deployment
# seed it with the newest tag present in BOTH ECR repositories.
ensure_release_tag() {
  local name tag
  name="$(release_param "$ENV" image-tag)"
  aws ssm get-parameter --name "$name" >/dev/null 2>&1 && return 0
  list_tags() {   # oldest -> newest
    aws ecr describe-images --repository-name "${PROJECT_NAME}/$1" \
      --query 'sort_by(imageDetails,&imagePushedAt)[].imageTags[0]' --output text | tr '\t' '\n' | grep -v '^None$' || true
  }
  tag=$(list_tags backend | grep -Fx -f <(list_tags frontend) | tail -1 || true)
  [[ -n "$tag" ]] || return 1
  aws ssm put-parameter --name "$name" --type String --value "$tag" >/dev/null
  warn "seeded $name = $tag (first deployment)"
}

plan_stack() {
  local comp=$1 stack template cs
  stack="$(stack_name "$ENV" "$comp")"; template="$REPO_ROOT/infra/cloudformation/${comp}.yaml"
  if ! stack_exists "$stack"; then
    log "PLAN $stack: stack does not exist -> will be CREATED"
    echo "- **$stack**: will be created" >> "$SUMMARY"; return 0
  fi
  cs="plan-$(date +%s)"
  local pfile; pfile="$(mktemp)"
  params_for "$comp" | jq -R '{ParameterKey: (split("=")[0]), ParameterValue: (split("=")[1:] | join("="))}' | jq -s . > "$pfile"
  aws cloudformation create-change-set --stack-name "$stack" --change-set-name "$cs" \
    --template-body "file://$template" --parameters "file://$pfile" \
    --capabilities CAPABILITY_NAMED_IAM --role-arn "$EXEC_ROLE" >/dev/null
  aws cloudformation wait change-set-create-complete --stack-name "$stack" --change-set-name "$cs" 2>/dev/null || true
  local changes
  changes=$(aws cloudformation describe-change-set --stack-name "$stack" --change-set-name "$cs" \
    --query 'Changes[].ResourceChange.[Action,LogicalResourceId,ResourceType,Replacement]' --output text)
  if [[ -z "$changes" ]]; then
    log "PLAN $stack: no changes"; echo "- **$stack**: no changes" >> "$SUMMARY"
  else
    log "PLAN $stack (Action  LogicalId  Type  Replacement):"; echo "$changes"
    { echo "- **$stack**:"; echo '```'; echo "$changes"; echo '```'; } >> "$SUMMARY"
  fi
  aws cloudformation delete-change-set --stack-name "$stack" --change-set-name "$cs"
}

apply_stack() {
  local comp=$1 stack template
  stack="$(stack_name "$ENV" "$comp")"; template="$REPO_ROOT/infra/cloudformation/${comp}.yaml"
  local -a p=(); while IFS= read -r kv; do p+=("$kv"); done < <(params_for "$comp")
  log "APPLY $stack"
  aws cloudformation deploy --stack-name "$stack" --template-file "$template" \
    --parameter-overrides "${p[@]}" \
    --capabilities CAPABILITY_NAMED_IAM --role-arn "$EXEC_ROLE" \
    --s3-bucket "$BUCKET" --s3-prefix "cfn/${ENV}" \
    --tags "Project=${PROJECT_NAME}" "Environment=${ENV}" "ManagedBy=CloudFormation" \
    --no-fail-on-empty-changeset
  ok "$stack is up to date"
}

echo "### Infrastructure ${MODE} - ${ENV}" >> "$SUMMARY"
for comp in "${STACKS[@]}"; do
  [[ -f "$REPO_ROOT/infra/cloudformation/${comp}.yaml" ]] || die "unknown stack '$comp'"
  if [[ "$comp" == ecs ]] && ! ensure_release_tag; then
    warn "no application image in ECR yet - skipping ecs stack (run build-and-push.sh, then re-run)"
    continue
  fi
  if [[ "$MODE" == plan ]]; then plan_stack "$comp"; else apply_stack "$comp"; fi
done

if [[ "$MODE" == apply ]]; then
  for comp in ecs ec2; do
    s="$(stack_name "$ENV" "$comp")"
    stack_exists "$s" && ok "$comp URL: $(stack_output "$s" AppUrl)"
  done
fi
exit 0
