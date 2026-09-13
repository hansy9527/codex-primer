#!/usr/bin/env bash
set -u

BASE_DIR="/opt/codex-primer"
HISTORY_DIR="$BASE_DIR/state/history"
CONFIG_FILE="$BASE_DIR/config/notify.env"

APP_TZ="Asia/Shanghai"
SLOT="${1:-}"

if [ -z "$SLOT" ]; then
  echo "Usage: $0 HH:MM" >&2
  exit 2
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Notify config not found: $CONFIG_FILE" >&2
  exit 3
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

LOCAL_DATE="$(TZ="$APP_TZ" date +'%Y%m%d')"
SLOT_FILE_PART="${SLOT//:/-}"

LATEST_MATCH="$(
  find "$HISTORY_DIR" -maxdepth 1 -type f \
    -name "${LOCAL_DATE}_*_${SLOT_FILE_PART}.json" \
    -printf '%T@ %p\n' 2>/dev/null \
  | sort -nr \
  | head -n 1 \
  | cut -d' ' -f2-
)"

if [ -z "$LATEST_MATCH" ] || [ ! -f "$LATEST_MATCH" ]; then
  TITLE="⚠️ Codex Primer · $SLOT"
  BODY="未发现该时段的执行结果。
北京时间：$(TZ="$APP_TZ" date +'%Y-%m-%d %H:%M:%S')
可能原因：计划任务未启动、执行仍未结束或状态文件写入失败。"
else
  SLOT_VALUE="$(grep -oP '"slot"\s*:\s*"\K[^"]+' "$LATEST_MATCH" || true)"
  STARTED_LOCAL="$(grep -oP '"started_at_local"\s*:\s*"\K[^"]+' "$LATEST_MATCH" || true)"
  FINISHED_LOCAL="$(grep -oP '"finished_at_local"\s*:\s*"\K[^"]+' "$LATEST_MATCH" || true)"
  MODEL="$(grep -oP '"model"\s*:\s*"\K[^"]+' "$LATEST_MATCH" || true)"
  EXIT_CODE="$(grep -oP '"exit_code"\s*:\s*\K[0-9]+' "$LATEST_MATCH" || true)"
  RESULT="$(grep -oP '"result"\s*:\s*"\K[^"]+' "$LATEST_MATCH" || true)"
  LOG_FILE="$(grep -oP '"log_file"\s*:\s*"\K[^"]+' "$LATEST_MATCH" || true)"

  if [ "$RESULT" = "success" ]; then
    TITLE="✅ Codex Primer · $SLOT"
    BODY="执行成功
模型：$MODEL
开始：$STARTED_LOCAL
完成：$FINISHED_LOCAL
返回：OK"
  else
    ERROR_LINE=""

    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
      ERROR_LINE="$(
        grep -Ei \
          'ERROR:|error:|failed|unsupported|authentication|unauthorized|forbidden|timed out|timeout' \
          "$LOG_FILE" \
        | tail -n 1 \
        | sed 's/[[:cntrl:]]//g' \
        | cut -c1-200 \
        || true
      )"
    fi

    TITLE="❌ Codex Primer · $SLOT"
    BODY="执行失败
模型：$MODEL
退出码：${EXIT_CODE:-unknown}
开始：$STARTED_LOCAL
完成：$FINISHED_LOCAL"

    if [ -n "$ERROR_LINE" ]; then
      BODY="${BODY}
错误：$ERROR_LINE"
    fi
  fi
fi

PAYLOAD="$(
python3 - "$TITLE" "$BODY" <<'PY'
import json
import sys

title = sys.argv[1]
body = sys.argv[2]

print(json.dumps({
    "title": title,
    "body": body,
    "group": "codex-primer"
}, ensure_ascii=False))
PY
)"

curl -fsS -X POST "${BARK_SERVER}/${BARK_KEY}/" \
  -H "Content-Type: application/json" \
  --data-binary "$PAYLOAD" \
  >/dev/null

echo "Bark notification sent for slot $SLOT"
