#!/usr/bin/env python3
"""Fixed SSH interface for the local Codex Primer runner."""
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

ROOT = Path('/opt/codex-primer')
TOKEN = re.compile(r'[A-Za-z0-9_-]{1,100}')

def system(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=12, check=True).stdout.strip()

def running():
    units = system('systemctl', 'list-units', 'codex-primer@*.service', '--state=active,activating,deactivating', '--no-legend', '--plain')
    if units:
        return True
    with (ROOT/'run/prime.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        return False

def record_path(identifier):
    if not isinstance(identifier, str) or not TOKEN.fullmatch(identifier):
        raise ValueError('无效的记录编号')
    path = ROOT/'state/history'/(identifier+'.json')
    if path.is_symlink() or not path.is_file():
        raise ValueError('记录不存在')
    return path

def read_record(path):
    if path.stat().st_size > 128*1024:
        raise ValueError('记录过大')
    data = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(data, dict) or data.get('result') not in ('success', 'failure'):
        raise ValueError('记录格式无效')
    return data

def public_record(path, data):
    fields = {'slot':'slot', 'started':'started_at_local', 'finished':'finished_at_local',
              'result':'result', 'reason':'failure_reason', 'model':'model',
              'attempts':'attempts_used', 'max_attempts':'max_attempts', 'exit_code':'exit_code'}
    result = {'id':path.stem}
    for key, field in fields.items():
        value = data.get(field, '')
        result[key] = value[:1200] if isinstance(value, str) else value if isinstance(value, (int, float, type(None))) else ''
    return result

def config():
    values = {}
    for line in (ROOT/'config/app.env').read_text(encoding='utf-8').splitlines():
        match = re.match(r'^\s*(?:export\s+)?(MODEL|APP_TZ|SCHEDULE_TIMES)=(.*)$', line)
        if match:
            parts = shlex.split(match[2], comments=True)
            values[match[1]] = ' '.join(parts)[:500]
    return values

def status():
    records = []
    for path in sorted((ROOT/'state/history').glob('*.json'), reverse=True)[:300]:
        if not TOKEN.fullmatch(path.stem) or path.is_symlink():
            continue
        try:
            records.append(public_record(path, read_record(path)))
        except (OSError, ValueError, TypeError):
            continue
    timer = dict(line.split('=',1) for line in system('systemctl','show','codex-primer.timer',
                 '-p','ActiveState','-p','UnitFileState','-p','NextElapseUSecRealtime').splitlines() if '=' in line)
    return {'host':'shandun', 'running':running(), 'records':records[:100],
            'last':records[0] if records else None, 'timer':timer, 'config':config(), 'checkedAt':int(time.time())}

def logs(identifier):
    record = read_record(record_path(identifier))
    history = (ROOT/'state/history').resolve()
    files = [record.get('log_file')] + [a.get('log_file') for a in record.get('attempts', [])[:10] if isinstance(a, dict)]
    seen, parts = set(), []
    for filename in files:
        if not isinstance(filename, str):
            continue
        path = Path(filename)
        if path.is_symlink() or path.resolve().parent != history or path.suffix != '.log' or path in seen or not path.is_file():
            continue
        seen.add(path)
        with path.open('rb') as stream:
            stream.seek(max(0, path.stat().st_size-18000))
            text = stream.read(18000).decode('utf-8', errors='replace')
        text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text)
        text = re.sub(r'(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+', r'\1[REDACTED]', text)
        text = re.sub(r'\bsk-[A-Za-z0-9_-]{12,}', '[REDACTED]', text)
        parts.append('===== '+path.name+' =====\n'+text)
    return {'id':identifier, 'log':'\n\n'.join(parts)[-60000:] or '日志不存在'}

def trigger(identifier=None):
    if identifier is not None and read_record(record_path(identifier))['result'] != 'failure':
        raise ValueError('只能重试失败记录')
    # Serialize requests, including the short interval before systemd starts the worker.
    with (ROOT/'run/web-control.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if running():
            return {'accepted':False, 'message':'任务已在运行，未重复启动'}
        system('systemctl','start','--no-block','codex-primer@manual.service')
        return {'accepted':True, 'message':'执行请求已提交至 shandun，请稍后手动刷新；任务完成后按原配置发送通知'}

def schedule(enabled):
    with (ROOT/'run/web-control.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        system('systemctl', 'enable' if enabled else 'disable', '--now', 'codex-primer.timer')
        value = status()
        value['message'] = '自动定时运行已开启' if enabled else '自动定时运行已关闭；正在执行的任务继续完成，仍可手动运行'
        return value

def main(command):
    args = command.split(' ')
    if args in (['schedule', 'on'], ['schedule', 'off']):
        return schedule(args[1] == 'on')
    if args == ['status']:
        return status()
    if args == ['run']:
        return trigger()
    if len(args)==2 and args[0] in ('log','retry') and TOKEN.fullmatch(args[1]):
        return logs(args[1]) if args[0]=='log' else trigger(args[1])
    raise ValueError('不支持的 Primer 操作')

if __name__ == '__main__':
    try:
        if len(sys.argv)!=2:
            raise ValueError('无效命令')
        print(json.dumps(main(sys.argv[1]), ensure_ascii=False))
    except ValueError as exc:
        print(json.dumps({'error':str(exc), 'invalid':True}, ensure_ascii=False))
        sys.exit(2)
    except Exception:
        print(json.dumps({'error':'Primer 控制接口暂不可用，请稍后刷新'}, ensure_ascii=False))
        sys.exit(1)
