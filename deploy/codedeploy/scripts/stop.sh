#!/bin/bash
set -euo pipefail
systemctl stop r2app-frontend.service 2>/dev/null || true
systemctl stop r2app-backend.service 2>/dev/null || true
