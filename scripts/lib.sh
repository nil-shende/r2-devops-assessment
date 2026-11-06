#!/usr/bin/env bash
# Shared helpers for every script. Both GitHub Actions and AWS CodeBuild call
# the SAME scripts, so the two CI/CD systems can never drift apart.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
export PROJECT_NAME="${PROJECT_NAME:-r2app}"
export AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

require() { for c in "$@"; do command -v "$c" >/dev/null || die "missing required tool: $c"; done; }

account_id() { aws sts get-caller-identity --query Account --output text; }
ecr_registry() { echo "$(account_id).dkr.ecr.${AWS_REGION}.amazonaws.com"; }
artifacts_bucket() { echo "${PROJECT_NAME}-artifacts-$(account_id)-${AWS_REGION}"; }

stack_name() { echo "${PROJECT_NAME}-$1-$2"; }   # stack_name <env> <component>

stack_exists() {
  local status
  status=$(aws cloudformation describe-stacks --stack-name "$1" \
            --query 'Stacks[0].StackStatus' --output text 2>/dev/null) || return 1
  [[ "$status" != "REVIEW_IN_PROGRESS" && "$status" != "DELETE_COMPLETE" ]]
}

stack_output() {   # stack_output <stack> <OutputKey>
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

validate_env() {
  case "${1:-}" in dev|staging|prod) ;; *) die "environment must be dev | staging | prod (got '${1:-}')";; esac
}

release_param() { echo "/${PROJECT_NAME}/$1/release/$2"; }   # release_param <env> image-tag|previous-image-tag
