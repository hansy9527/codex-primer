#!/usr/bin/env bash
set -u

BASE_DIR="/opt/codex-primer"
CODEX_HOME="$BASE_DIR/codex-home"
STATE_DIR="$BASE_DIR/state"
HISTORY_DIR="$STATE_DIR/history"
LOG_DIR="$BASE_DIR/logs"
LOCK_FILE="$BASE_DIR/run/prime.lock"

APP_TZ="Asia/Shanghai"
MODEL="gpt-5.6-luna"
PROMPT="Reply with exactly: OK"
TIMEOUT_SECONDS=180

SLOT="${1:-manual}"

# 北京时间用于业务日期、文件名和用户展示
LOCAL_DATE="$(TZ="$APP_TZ" date +'%Y%m%d')"
LOCAL_TIME="$(TZ="$APP_TZ" date +'%H%M%S')"
STARTED_AT_LOCAL="$(TZ="$APP_TZ" date +'%Y-%m-%dT%H:%M:%S%:z')"

# UTC 用于技术排查
STARTED_AT_UTC="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

SLOT_FILE_PART="${SLOT//:/-}"
RUN_ID="${LOCAL_DATE}_${LOCAL_TIME}"

OUTPUT_FILE="$HISTORY_DIR/${RUN_ID}_${SLOT_FILE_PART}.log"
STATE_FILE="$HISTORY_DIR/${RUN_ID}_${SLOT_FILE_PART}.json"
LATEST_FILE="$STATE_DIR/latest.json"

mkdir -p "$HISTORY_DIR" "$LOG_DIR"

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
  echo "Another Codex primer process is already running." >&2
  exit 75
fi

{
  echo "===== Codex Primer ====="
  echo "slot=$SLOT"
  echo "timezone=$APP_TZ"
  echo "started_at_local=$STARTED_AT_LOCAL"
  echo "started_at_utc=$STARTED_AT_UTC"
  echo "model=$MODEL"
} >> "$OUTPUT_FILE"

export CODEX_HOME

set +e
timeout "$TIMEOUT_SECONDS" \
  codex -m "$MODEL" \
  exec \
  --skip-git-repo-check \
  "$PROMPT" \
  >> "$OUTPUT_FILE" 2>&1

EXIT_CODE=$?
set -e

FINISHED_AT_LOCAL="$(TZ="$APP_TZ" date +'%Y-%m-%dT%H:%M:%S%:z')"
FINISHED_AT_UTC="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

if [ "$EXIT_CODE" -eq 0 ] && grep -Eq '^OK$' "$OUTPUT_FILE"; then
  RESULT="success"
else
  RESULT="failure"
fi

cat > "$STATE_FILE" <<JSON
{
  "slot": "$SLOT",
  "timezone": "$APP_TZ",
  "started_at_local": "$STARTED_AT_LOCAL",
  "finished_at_local": "$FINISHED_AT_LOCAL",
  "started_at_utc": "$STARTED_AT_UTC",
  "finished_at_utc": "$FINISHED_AT_UTC",
  "model": "$MODEL",
  "exit_code": $EXIT_CODE,
  "result": "$RESULT",
  "log_file": "$OUTPUT_FILE"
}
JSON

cp "$STATE_FILE" "$LATEST_FILE"

{
  echo "finished_at_local=$FINISHED_AT_LOCAL"
  echo "finished_at_utc=$FINISHED_AT_UTC"
  echo "exit_code=$EXIT_CODE"
  echo "result=$RESULT"
  echo
} >> "$OUTPUT_FILE"

exit "$EXIT_CODE"
