#!/usr/bin/env bash
# Roll the APPLICATION back by redeploying an older immutable release.
# Usage: rollback-app.sh <env> [tag]     (default tag = the previous release recorded in SSM)
source "$(dirname "$0")/lib.sh"
ENV="${1:-}"; validate_env "$ENV"
TAG="${2:-}"
if [[ -z "$TAG" ]]; then
  TAG="$(aws ssm get-parameter --name "$(release_param "$ENV" previous-image-tag)" \
         --query Parameter.Value --output text 2>/dev/null)" || die "no previous release recorded for $ENV - pass a tag"
fi
warn "Rolling $ENV back to release $TAG"
exec bash "$(dirname "$0")/deploy-app.sh" "$ENV" "$TAG"
