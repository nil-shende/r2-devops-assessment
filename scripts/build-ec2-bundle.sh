#!/usr/bin/env bash
# Builds the CodeDeploy bundle for the NON-containerized deployment:
#   dist/ec2-bundle-<tag>.zip
#     appspec.yml, scripts/, systemd/      <- from deploy/codedeploy
#     frontend/                            <- Next.js standalone server (pre-built, no npm on the server)
#     backend/                             <- Python source + requirements.txt
#     version.env                          <- APP_VERSION=<tag>
# Usage: build-ec2-bundle.sh <tag>
source "$(dirname "$0")/lib.sh"
TAG="${1:?usage: build-ec2-bundle.sh <tag>}"
require npm zip

OUT="$REPO_ROOT/dist/ec2-bundle"
rm -rf "$OUT" && mkdir -p "$OUT/frontend" "$OUT/backend"

log "Building Next.js standalone output"
cd "$REPO_ROOT/apps/frontend" || exit 1
[[ -d node_modules ]] || npm ci --no-audit --no-fund
NEXT_TELEMETRY_DISABLED=1 npm run build >/dev/null
cp -R .next/standalone/. "$OUT/frontend/"
mkdir -p "$OUT/frontend/.next" && cp -R .next/static "$OUT/frontend/.next/static"
cp -R public "$OUT/frontend/public"

log "Copying backend source"
cp -R "$REPO_ROOT/apps/backend/app" "$OUT/backend/app"
cp "$REPO_ROOT/apps/backend/requirements.txt" "$OUT/backend/"
find "$OUT/backend" -name '__pycache__' -prune -exec rm -rf {} +

cp -R "$REPO_ROOT/deploy/codedeploy/." "$OUT/"
chmod +x "$OUT"/scripts/*.sh
echo "APP_VERSION=${TAG}" > "$OUT/version.env"

cd "$OUT" && rm -f "../ec2-bundle-${TAG}.zip" && zip -qr "../ec2-bundle-${TAG}.zip" .
ok "bundle: dist/ec2-bundle-${TAG}.zip ($(du -h "../ec2-bundle-${TAG}.zip" | cut -f1))"
