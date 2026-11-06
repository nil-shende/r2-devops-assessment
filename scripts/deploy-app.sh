#!/usr/bin/env bash
# APPLICATION deployment - touches NO CloudFormation stack.
#   1. checks that the immutable artifacts for <tag> exist
#   2. ECS : registers a new task-definition revision with the new image and
#            updates the services (rolling update, circuit breaker auto-rollback)
#   3. EC2 : creates a CodeDeploy deployment of s3://.../ec2/<tag>.zip
#            (in-place, ALB traffic control, auto-rollback on failure/alarm)
#   4. records the release in SSM Parameter Store (current + previous tag)
# Either compute stack may be absent (e.g. you only deploy ECS to save cost).
# Usage: deploy-app.sh <env> <tag>
source "$(dirname "$0")/lib.sh"
ENV="${1:-}"; TAG="${2:-}"
validate_env "$ENV"; [[ -n "$TAG" ]] || die "usage: deploy-app.sh <env> <tag>"
require aws jq

REGISTRY="$(ecr_registry)"
BUCKET="$(artifacts_bucket)"
CLUSTER="${PROJECT_NAME}-${ENV}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

log "Deploying release $TAG to $ENV"
for app in frontend backend; do
  aws ecr describe-images --repository-name "${PROJECT_NAME}/${app}" --image-ids imageTag="$TAG" >/dev/null 2>&1 \
    || die "image ${PROJECT_NAME}/${app}:${TAG} not found - run build-and-push.sh first"
done
aws s3api head-object --bucket "$BUCKET" --key "ec2/${TAG}.zip" >/dev/null 2>&1 \
  || die "bundle s3://$BUCKET/ec2/${TAG}.zip not found - run build-and-push.sh first"

CURRENT_TAG="$(aws ssm get-parameter --name "$(release_param "$ENV" image-tag)" \
               --query Parameter.Value --output text 2>/dev/null || true)"

# ---------------------------------------------------------------- ECS (containerized)
deploy_ecs_service() {
  local app=$1 svc="${PROJECT_NAME}-${ENV}-$1" image="$REGISTRY/${PROJECT_NAME}/$1:$TAG"
  local cur_td new_td td state

  cur_td=$(aws ecs describe-services --cluster "$CLUSTER" --services "$svc" \
            --query 'services[0].taskDefinition' --output text)
  aws ecs describe-task-definition --task-definition "$cur_td" --query taskDefinition > "$WORK/$app-cur.json"
  jq --arg img "$image" '
      .containerDefinitions[0].image = $img
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
            .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)' \
     "$WORK/$app-cur.json" > "$WORK/$app-new.json"

  new_td=$(aws ecs register-task-definition --cli-input-json "file://$WORK/$app-new.json" \
            --query taskDefinition.taskDefinitionArn --output text)
  log "ECS $svc -> $new_td"
  aws ecs update-service --cluster "$CLUSTER" --service "$svc" --task-definition "$new_td" >/dev/null

  for _ in $(seq 1 80); do            # up to 20 minutes
    read -r td state < <(aws ecs describe-services --cluster "$CLUSTER" --services "$svc" \
      --query 'services[0].deployments[?status==`PRIMARY`]|[0].[taskDefinition,rolloutState]' --output text)
    if [[ "$td" != "$new_td" ]]; then
      die "ECS $svc: deployment circuit breaker rolled back to $td"
    fi
    case "$state" in
      COMPLETED) ok "ECS $svc is running $TAG"; return 0 ;;
      FAILED)    die "ECS $svc: rollout FAILED (circuit breaker will restore the previous revision)" ;;
    esac
    sleep 15
  done
  die "ECS $svc: timed out waiting for the rollout"
}

if stack_exists "$(stack_name "$ENV" ecs)"; then
  deploy_ecs_service backend      # API first, so the new UI never talks to an old API
  deploy_ecs_service frontend
else
  warn "stack $(stack_name "$ENV" ecs) not found - skipping containerized deployment"
fi

# ---------------------------------------------------------------- EC2 (non-containerized, CodeDeploy)
if stack_exists "$(stack_name "$ENV" ec2)"; then
  APP="${PROJECT_NAME}-${ENV}-ec2"; DG="${PROJECT_NAME}-${ENV}-ec2-dg"
  DEP_ID=$(aws deploy create-deployment \
            --application-name "$APP" --deployment-group-name "$DG" \
            --s3-location "bucket=$BUCKET,key=ec2/${TAG}.zip,bundleType=zip" \
            --description "release $TAG" --query deploymentId --output text)
  log "CodeDeploy $DEP_ID started (https://${AWS_REGION}.console.aws.amazon.com/codesuite/codedeploy/deployments/$DEP_ID)"
  if ! aws deploy wait deployment-successful --deployment-id "$DEP_ID"; then
    aws deploy get-deployment --deployment-id "$DEP_ID" \
      --query 'deploymentInfo.[status,errorInformation.code,errorInformation.message]' --output text >&2 || true
    die "CodeDeploy deployment failed - CodeDeploy automatically rolled back to the last good revision"
  fi
  ok "EC2 Auto Scaling group is running $TAG"
else
  warn "stack $(stack_name "$ENV" ec2) not found - skipping non-containerized deployment"
fi

# ---------------------------------------------------------------- Record the release
# Written only after success. The ECS stack reads image-tag, so a later
# infrastructure deployment keeps exactly this release.
if [[ -n "$CURRENT_TAG" && "$CURRENT_TAG" != "$TAG" ]]; then
  aws ssm put-parameter --name "$(release_param "$ENV" previous-image-tag)" --type String \
    --value "$CURRENT_TAG" --overwrite >/dev/null
fi
aws ssm put-parameter --name "$(release_param "$ENV" image-tag)" --type String \
  --value "$TAG" --overwrite >/dev/null
ok "release $TAG recorded for $ENV (previous: ${CURRENT_TAG:-none})"
