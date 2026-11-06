#!/usr/bin/env bash
# Unit tests + type checks for both applications (no AWS access needed).
source "$(dirname "$0")/lib.sh"

log "Backend: pytest"
cd "$REPO_ROOT/apps/backend" || exit 1
python3 -m venv .venv
.venv/bin/pip install --quiet -r requirements-dev.txt
.venv/bin/python -m pytest -q

log "Frontend: build + type check"
cd "$REPO_ROOT/apps/frontend" || exit 1
npm ci --no-audit --no-fund
NEXT_TELEMETRY_DISABLED=1 npm run build
npm run typecheck
ok "all tests passed"
