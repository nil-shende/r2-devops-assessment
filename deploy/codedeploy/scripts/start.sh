#!/bin/bash
set -euo pipefail
systemctl daemon-reload
systemctl enable r2app-backend.service r2app-frontend.service
systemctl restart r2app-backend.service
systemctl restart r2app-frontend.service
