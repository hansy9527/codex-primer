#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$BASE_DIR/config/app.env"
SLOT="$(TZ="$APP_TZ" date +%H:%M)"
systemctl start "codex-primer@${SLOT}.service"
