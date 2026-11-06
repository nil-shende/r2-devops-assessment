#!/bin/bash
# Install Python dependencies into an isolated virtualenv and register systemd units.
set -euo pipefail
REL=/opt/r2app/release
PY=$(command -v python3.11 || command -v python3)

"$PY" -m venv "$REL/backend/.venv"
"$REL/backend/.venv/bin/pip" install --quiet --upgrade pip
"$REL/backend/.venv/bin/pip" install --quiet -r "$REL/backend/requirements.txt"

install -m 0644 "$REL/systemd/r2app-backend.service"  /etc/systemd/system/
install -m 0644 "$REL/systemd/r2app-frontend.service" /etc/systemd/system/

chown -R r2app:r2app "$REL" /var/log/r2app
