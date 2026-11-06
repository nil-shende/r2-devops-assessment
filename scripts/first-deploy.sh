#!/usr/bin/env bash
# Convenience: first end-to-end deployment of one environment from your laptop
# (after bootstrap.sh). Order matters: images must exist before the ECS stack.
# Usage: first-deploy.sh [env]      (default dev)
source "$(dirname "$0")/lib.sh"
ENV="${1:-dev}"; validate_env "$ENV"
TAG="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
bash "$REPO_ROOT/scripts/build-and-push.sh" "$TAG"          # 1. artifacts
bash "$REPO_ROOT/scripts/deploy-infra.sh" "$ENV" apply      # 2. infrastructure (ECS starts on $TAG)
bash "$REPO_ROOT/scripts/deploy-app.sh" "$ENV" "$TAG"       # 3. app release (CodeDeploy to EC2, ECS confirm)
