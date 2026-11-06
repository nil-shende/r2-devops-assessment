#!/usr/bin/env bash
# Static checks for Infrastructure as Code (runs in PRs and in the infra pipeline).
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT" || exit 1
command -v cfn-lint >/dev/null || pip install --quiet cfn-lint
log "cfn-lint"
cfn-lint                                   # config in .cfnlintrc.yaml
for f in infra/environments/*.json; do jq -e . "$f" >/dev/null || die "invalid JSON: $f"; done
if [[ "${VALIDATE_WITH_AWS:-false}" == true ]]; then
  for t in infra/cloudformation/*.yaml; do
    aws cloudformation validate-template --template-body "file://$t" >/dev/null && ok "$t"
  done
fi
ok "templates valid"
