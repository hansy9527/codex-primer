#!/usr/bin/env bash
set -u
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HISTORY_DIR="$BASE_DIR/state/history"
CONFIG_FILE="$BASE_DIR/config/notify.env"
# shellcheck disable=SC1091
source "$BASE_DIR/config/app.env"
SLOT="${1:-}"
if [ -z "$SLOT" ]; then echo "Usage: $0 HH:MM" >&2; exit 2; fi
if [ ! -f "$CONFIG_FILE" ]; then echo "Notify config not found: $CONFIG_FILE" >&2; exit 3; fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"
LOCAL_DATE="$(TZ="$APP_TZ" date +'%Y%m%d')"
SLOT_PART="${SLOT//:/-}"
LATEST_MATCH="$(find "$HISTORY_DIR" -maxdepth 1 -type f -name "${LOCAL_DATE}_*_${SLOT_PART}.json" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
PAYLOAD="$(python3 - "$LATEST_MATCH" "$SLOT" <<'PY'
import json,os,sys
path,slot=sys.argv[1:]
if not path or not os.path.isfile(path):
    title=f"⚠️ Codex Primer · {slot}"
    body="未发现该时段的执行结果；任务可能未启动、仍在运行或状态文件写入失败。"
else:
    with open(path) as f:d=json.load(f)
    model=d.get("model","unknown")
    started=d.get("started_at_local","unknown")
    finished=d.get("finished_at_local","unknown")
    used=d.get("attempts_used",1)
    maximum=d.get("max_attempts",1)
    if d.get("result")=="success":
        title=f"✅ Codex Primer · {slot}"
        body=f"执行成功\n模型：{model}\n尝试：{used}/{maximum}\n开始：{started}\n完成：{finished}\n返回：OK"
    else:
        title=f"❌ Codex Primer · {slot}"
        reason=d.get("failure_reason") or "未返回详细错误，请查看 VPS 日志"
        body=f"重试耗尽，执行失败\n模型：{model}\n尝试：{used}/{maximum}\n退出码：{d.get('exit_code','unknown')}\n开始：{started}\n完成：{finished}\n原因：{reason}"
        for a in d.get("attempts",[]):
            body+=f"\n第{a.get('attempt')}次：退出码 {a.get('exit_code')}；{a.get('reason') or '未返回详细错误'}"
        body+=f"\n日志：{d.get('log_file','unknown')}"
print(json.dumps(dict(title=title,body=body,group="codex-primer"),ensure_ascii=False))
PY
)"
curl -fsS --connect-timeout 10 --max-time 25 -X POST "${BARK_SERVER}/${BARK_KEY}/" -H "Content-Type: application/json" --data-binary "$PAYLOAD" >/dev/null
echo "Bark notification sent for slot $SLOT"
