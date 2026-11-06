#!/bin/bash
# Start every deployment from a clean release directory.
set -euo pipefail
rm -rf /opt/r2app/release
mkdir -p /opt/r2app/release /var/log/r2app
id r2app >/dev/null 2>&1 || useradd --system --home /opt/r2app --shell /sbin/nologin r2app
