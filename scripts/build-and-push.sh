#!/usr/bin/env bash
# BUILD ONCE: produce every deployable artifact for one commit and store it.
#   * Docker images  -> ECR  <project>/frontend:<tag>, <project>/backend:<tag>   (containerized)
#   * CodeDeploy zip -> s3://<artifacts>/ec2/<tag>.zip                          (non-containerized)
# Artifacts are immutable; if they already exist for this tag they are reused,
# so GitHub Actions and CodePipeline can both run without conflicts.
# Usage: build-and-push.sh <tag>      (tag = git commit SHA)
source "$(dirname "$0")/lib.sh"
TAG="${1:?usage: build-and-push.sh <tag>}"
require aws docker jq

REGISTRY="$(ecr_registry)"
BUCKET="$(artifacts_bucket)"

log "Logging in to ECR $REGISTRY"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null

for app in backend frontend; do
  repo="${PROJECT_NAME}/${app}"
  if aws ecr describe-images --repository-name "$repo" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
    ok "image $repo:$TAG already exists - skipping build"
    continue
  fi
  log "Building $repo:$TAG"
  docker build --pull --build-arg APP_VERSION="$TAG" -t "$REGISTRY/$repo:$TAG" "$REPO_ROOT/apps/$app"
  docker push "$REGISTRY/$repo:$TAG"
  ok "pushed $REGISTRY/$repo:$TAG"
done

KEY="ec2/${TAG}.zip"
if aws s3api head-object --bucket "$BUCKET" --key "$KEY" >/dev/null 2>&1; then
  ok "bundle s3://$BUCKET/$KEY already exists - skipping"
else
  bash "$REPO_ROOT/scripts/build-ec2-bundle.sh" "$TAG"
  aws s3 cp "$REPO_ROOT/dist/ec2-bundle-${TAG}.zip" "s3://$BUCKET/$KEY" --only-show-errors
  ok "uploaded s3://$BUCKET/$KEY"
fi
