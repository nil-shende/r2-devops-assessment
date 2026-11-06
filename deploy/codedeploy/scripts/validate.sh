#!/bin/bash
# Fail the deployment (=> CodeDeploy auto-rollback) unless both services answer.
set -uo pipefail
check() {
  local url=$1
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 3 "$url" >/dev/null; then echo "OK  $url"; return 0; fi
    sleep 4
  done
  echo "FAIL $url"; return 1
}
check http://127.0.0.1:8000/api/health && check http://127.0.0.1:3000/healthz
