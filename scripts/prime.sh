#!/usr/bin/env bash
set -u
BASE_DIR="/opt/codex-primer"
CODEX_HOME="$BASE_DIR/codex-home"
HISTORY_DIR="$BASE_DIR/state/history"
LOCK_FILE="$BASE_DIR/run/prime.lock"
APP_TZ="Asia/Shanghai"
MODEL="gpt-5.6-luna"
PROMPT="Reply with exactly: OK"
TIMEOUT_SECONDS=180
MAX_ATTEMPTS=2
RETRY_DELAY_SECONDS=30
SLOT="${1:-manual}"
RUN_ID="$(TZ="$APP_TZ" date +'%Y%m%d_%H%M%S')"
SLOT_PART="${SLOT//:/-}"
PREFIX="$HISTORY_DIR/${RUN_ID}_${SLOT_PART}"
OUTPUT_FILE="$PREFIX.log"
STATE_FILE="$PREFIX.json"
mkdir -p "$HISTORY_DIR" "$BASE_DIR/run"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then echo "Another Codex primer process is already running." >&2; exit 75; fi
STARTED_AT_LOCAL="$(TZ="$APP_TZ" date +'%Y-%m-%dT%H:%M:%S%:z')"
STARTED_AT_UTC="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf '===== Codex Primer =====\nslot=%s\nstarted_at_local=%s\nmodel=%s\n' "$SLOT" "$STARTED_AT_LOCAL" "$MODEL" >"$OUTPUT_FILE"
export CODEX_HOME
ATTEMPT_RECORDS=()
RESULT=failure
EXIT_CODE=1
FAILURE_REASON=""
ATTEMPTS_USED=0
for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
  ATTEMPTS_USED="$attempt"
  ATTEMPT_LOG="${PREFIX}_attempt${attempt}.log"
  printf '%s\n' "$PROMPT" | timeout "$TIMEOUT_SECONDS" codex -m "$MODEL" exec --skip-git-repo-check - >"$ATTEMPT_LOG" 2>&1
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 0 ] && grep -Eq '^OK$' "$ATTEMPT_LOG"; then
    RESULT=success
    REASON=""
  elif [ "$EXIT_CODE" -eq 124 ]; then
    REASON="180 秒超时，Codex 未完成"
  elif [ "$EXIT_CODE" -eq 0 ]; then
    REASON="Codex 退出但未返回独立一行 OK"
  else
    REASON="Codex 异常退出，退出码 $EXIT_CODE"
  fi
  if [ "$RESULT" != success ]; then
    if grep -Eiq 'failed to refresh available models' "$ATTEMPT_LOG"; then
      REASON="$REASON；模型列表刷新失败"
    elif grep -Eiq '401|unauthorized|authentication failed' "$ATTEMPT_LOG"; then
      REASON="$REASON；疑似认证失败（401）"
    elif grep -Eiq '403|forbidden' "$ATTEMPT_LOG"; then
      REASON="$REASON；服务端拒绝访问（403）"
    elif grep -Eiq '429|rate.limit' "$ATTEMPT_LOG"; then
      REASON="$REASON；请求频率或额度限制（429）"
    elif grep -Eiq 'connection refused|connection reset|dns error|timed out|network error' "$ATTEMPT_LOG"; then
      REASON="$REASON；网络连接或请求超时"
    elif grep -Eiq 'ERROR|error:|failed' "$ATTEMPT_LOG"; then
      REASON="$REASON；出现其他错误，详见 VPS 尝试日志"
    fi
  fi
  ATTEMPT_RECORDS+=("$attempt|$EXIT_CODE|$RESULT|$REASON|$ATTEMPT_LOG")
  printf 'attempt=%s exit_code=%s result=%s reason=%s log=%s\n' "$attempt" "$EXIT_CODE" "$RESULT" "$REASON" "$ATTEMPT_LOG" >>"$OUTPUT_FILE"
  if [ "$RESULT" = success ]; then break; fi
  FAILURE_REASON="$REASON"
  if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then sleep "$RETRY_DELAY_SECONDS"; fi
done
FINISHED_AT_LOCAL="$(TZ="$APP_TZ" date +'%Y-%m-%dT%H:%M:%S%:z')"
FINISHED_AT_UTC="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
python3 - "$STATE_FILE" "$SLOT" "$APP_TZ" "$STARTED_AT_LOCAL" "$FINISHED_AT_LOCAL" "$STARTED_AT_UTC" "$FINISHED_AT_UTC" "$MODEL" "$EXIT_CODE" "$RESULT" "$OUTPUT_FILE" "$ATTEMPTS_USED" "$MAX_ATTEMPTS" "$FAILURE_REASON" "${ATTEMPT_RECORDS[@]}" <<'PY'
import json,sys
(path,slot,tz,start,finish,startutc,finishutc,model,code,result,log,used,maximum,reason,*rows)=sys.argv[1:]
attempts=[]
for row in rows:
    n,c,r,why,filename=row.split("|",4)
    attempts.append(dict(attempt=int(n),exit_code=int(c),result=r,reason=why,log_file=filename))
data=dict(slot=slot,timezone=tz,started_at_local=start,finished_at_local=finish,started_at_utc=startutc,finished_at_utc=finishutc,model=model,exit_code=int(code),result=result,log_file=log,attempts_used=int(used),max_attempts=int(maximum),failure_reason=reason if result!="success" else "",attempts=attempts)
with open(path,"w") as f: json.dump(data,f,ensure_ascii=False,indent=2);f.write("\n")
PY
cp "$STATE_FILE" "$BASE_DIR/state/latest.json"
printf 'finished_at_local=%s\nexit_code=%s\nresult=%s\n' "$FINISHED_AT_LOCAL" "$EXIT_CODE" "$RESULT" >>"$OUTPUT_FILE"

# Notify only after all attempts have completed and final state is durable.
# Keep the Codex outcome independent of Bark delivery status.
NOTIFY_EXIT=0
"$BASE_DIR/scripts/check-result.sh" "$SLOT" >>"$OUTPUT_FILE" 2>&1 || NOTIFY_EXIT=$?
if [ "$NOTIFY_EXIT" -ne 0 ]; then
  printf 'Bark notification failed: exit_code=%s\n' "$NOTIFY_EXIT" >>"$OUTPUT_FILE"
  echo "Bark notification failed (exit $NOTIFY_EXIT); see $OUTPUT_FILE" >&2
fi

if [ "$RESULT" = success ]; then exit 0; fi
if [ "$EXIT_CODE" -eq 0 ]; then exit 1; fi
exit "$EXIT_CODE"
