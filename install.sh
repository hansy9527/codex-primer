#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${1:-/opt/codex-primer}"
if [[ ! "$BASE_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]] || [[ "$BASE_DIR" == *"/../"* ]] || [[ "$BASE_DIR" == *"/./"* ]] || [[ "$BASE_DIR" == *"//"* ]]; then
  echo "Install directory must be an absolute path containing only letters, numbers, _, -, . and / (no traversal)." >&2
  exit 2
fi
BASE_DIR="${BASE_DIR%/}"
if [[ "$BASE_DIR" == "" || "$BASE_DIR" == "/" ]]; then echo "Invalid install directory" >&2; exit 2; fi
if (( EUID != 0 )); then echo "Run as root: sudo bash install.sh [install-directory]" >&2; exit 2; fi
mkdir -p "$BASE_DIR"/{scripts,config,codex-home,state/history,logs,run}
if [[ ! -f "$BASE_DIR/config/app.env" ]]; then
  cp "$SRC_DIR/config/app.env.example" "$BASE_DIR/config/app.env"
fi
if [[ ! -f "$BASE_DIR/config/notify.env" ]]; then
  cp "$SRC_DIR/config/notify.env.example" "$BASE_DIR/config/notify.env"
fi
if [[ ! -f "$BASE_DIR/codex-home/config.toml" ]]; then
  cp "$SRC_DIR/config/config.toml" "$BASE_DIR/codex-home/config.toml"
fi

# Validate configuration before replacing installed scripts or units.
# shellcheck disable=SC1091
source "$BASE_DIR/config/app.env"
export APP_TZ SCHEDULE_TIMES MODEL PROMPT TIMEOUT_SECONDS MAX_ATTEMPTS RETRY_DELAY_SECONDS
RENDER_DIR="$(mktemp -d)"
trap 'rm -rf "$RENDER_DIR"' EXIT
python3 - "$SRC_DIR" "$BASE_DIR" "$RENDER_DIR" <<'PY'
import os,re,sys
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from pathlib import Path
src,base,out=map(Path,sys.argv[1:])
env=os.environ
tz=env.get("APP_TZ","")
try:
    ZoneInfo(tz)
except (ZoneInfoNotFoundError,ValueError):
    sys.exit(f"Invalid APP_TZ: {tz!r}")
times=env.get("SCHEDULE_TIMES","").split()
if not times or len(times)!=len(set(times)):
    sys.exit("SCHEDULE_TIMES must contain one or more unique HH:MM values")
for t in times:
    if not re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]",t):
        sys.exit(f"Invalid time: {t!r}; expected HH:MM")
if not env.get("MODEL","").strip() or not env.get("PROMPT","").strip():
    sys.exit("MODEL and PROMPT must not be empty")
values={}
for key in ("TIMEOUT_SECONDS","MAX_ATTEMPTS","RETRY_DELAY_SECONDS"):
    try:
        values[key]=int(env[key])
    except (KeyError,ValueError):
        sys.exit(f"{key} must be an integer")
if values["TIMEOUT_SECONDS"]<1 or values["MAX_ATTEMPTS"]<1 or values["RETRY_DELAY_SECONDS"]<0:
    sys.exit("Timeout/attempts must be positive and retry delay nonnegative")
service_timeout=(values["TIMEOUT_SECONDS"]*values["MAX_ATTEMPTS"]
    +values["RETRY_DELAY_SECONDS"]*(values["MAX_ATTEMPTS"]-1)+120)
timer="""[Unit]
Description=Codex Primer Schedule

[Timer]
"""+ "".join(f"OnCalendar=*-*-* {t}:00 {tz}\n" for t in times)+"""AccuracySec=1s
RandomizedDelaySec=0
Persistent=true
Unit=codex-primer-dispatch.service

[Install]
WantedBy=timers.target
"""
(out/"codex-primer.timer").write_text(timer)
for name in ("codex-primer@.service","codex-primer-dispatch.service"):
    template=(src/"systemd"/(name+".template")).read_text()
    rendered=template.replace("__BASE_DIR__",str(base)).replace("__SERVICE_TIMEOUT__",str(service_timeout))
    (out/name).write_text(rendered)
print(f"Schedule: {', '.join(times)} ({tz})")
print(f"Install directory: {base}")
print(f"Service timeout: {service_timeout}s")
PY

install -m 700 "$SRC_DIR/scripts/prime.sh" "$BASE_DIR/scripts/prime.sh"
install -m 700 "$SRC_DIR/scripts/check-result.sh" "$BASE_DIR/scripts/check-result.sh"
install -m 700 "$SRC_DIR/scripts/dispatch.sh" "$BASE_DIR/scripts/dispatch.sh"
chmod 700 "$BASE_DIR/codex-home" "$BASE_DIR/config"
chmod 600 "$BASE_DIR/config/notify.env" "$BASE_DIR/config/app.env"
install -m 644 "$RENDER_DIR/codex-primer.timer" /etc/systemd/system/codex-primer.timer
install -m 644 "$RENDER_DIR/codex-primer-dispatch.service" /etc/systemd/system/codex-primer-dispatch.service
install -m 644 "$RENDER_DIR/codex-primer@.service" /etc/systemd/system/codex-primer@.service
systemctl daemon-reload
systemctl disable --now codex-primer-check.timer 2>/dev/null || true
systemctl enable --now codex-primer.timer
systemctl restart codex-primer.timer
echo "Installed. Configure Codex login and Bark key, then run: $BASE_DIR/scripts/prime.sh manual"
