#!/usr/bin/env bash
# Tear an environment down (reverse dependency order) to stop all charges.
# RDS leaves a final snapshot (DeletionPolicy: Snapshot) - delete it in the RDS
# console if you do not need it. Usage: destroy.sh <env> [--yes]
source "$(dirname "$0")/lib.sh"
ENV="${1:-}"; validate_env "$ENV"
if [[ "${2:-}" != "--yes" ]]; then
  read -r -p "Delete ALL ${PROJECT_NAME}-${ENV}-* stacks? type the env name to confirm: " c
  [[ "$c" == "$ENV" ]] || die "aborted"
fi
for comp in ec2 ecs monitoring database alb security network; do
  s="$(stack_name "$ENV" "$comp")"
  stack_exists "$s" || continue
  log "deleting $s"
  aws cloudformation delete-stack --stack-name "$s"
  aws cloudformation wait stack-delete-complete --stack-name "$s"
  ok "deleted $s"
done
for p in image-tag previous-image-tag; do
  aws ssm delete-parameter --name "$(release_param "$ENV" "$p")" 2>/dev/null || true
done
ok "environment $ENV removed"
