# Codex Primer

在 Linux VPS 上使用 systemd 定时调用 Codex CLI，并在执行完成后通过 Bark 推送结果。

## 功能

- 按北京时间每天 07:00、12:05、17:10、22:15 执行
- 使用模型 `gpt-5.6-luna`，发送简短测试提示词并验证返回 `OK`
- 每次最多尝试 2 次，每次超时 180 秒；失败后间隔 30 秒重试
- 完成后立即发送 Bark 成功或失败通知
- 保存运行状态及日志，并通过文件锁避免并发执行

## 环境要求

- Linux（systemd）
- Bash、Python 3、curl、flock、GNU timeout、Git
- Node.js、npm、Codex CLI
- 可用的 Codex 登录账号和 Bark Key

安装 Codex CLI：

```bash
npm install -g @openai/codex@latest
codex --version
```

## 安装

**当前版本的运行目录固定为 `/opt/codex-primer`。** 脚本和 systemd 单元使用了该绝对路径；如果希望安装在其他位置，需要同步修改 `scripts/prime.sh`、`scripts/check-result.sh` 和 `systemd/codex-primer@.service` 中的路径。

克隆仓库并部署：

```bash
git clone https://github.com/hansy9527/codex-primer.git /opt/codex-primer-repo
cd /opt/codex-primer-repo

mkdir -p /opt/codex-primer/{codex-home,scripts,state/history,logs,run,config}

cp scripts/prime.sh scripts/check-result.sh /opt/codex-primer/scripts/
cp config/config.toml /opt/codex-primer/codex-home/config.toml
cp config/notify.env.example /opt/codex-primer/config/notify.env

chmod 700 /opt/codex-primer/scripts/*.sh
chmod 700 /opt/codex-primer/codex-home /opt/codex-primer/config
chmod 600 /opt/codex-primer/config/notify.env

cp systemd/codex-primer.timer \
   systemd/codex-primer-dispatch.service \
   systemd/codex-primer@.service \
   /etc/systemd/system/
```

## 配置

### 1. Codex 登录

```bash
CODEX_HOME=/opt/codex-primer/codex-home codex login --device-auth
CODEX_HOME=/opt/codex-primer/codex-home codex login status
```

### 2. Bark 通知

编辑 `/opt/codex-primer/config/notify.env`：

```bash
BARK_SERVER="https://api.day.app"
BARK_KEY="replace-with-your-bark-key"
```

把 `BARK_KEY` 替换成自己的 Key。

### 3. 运行参数

在 `/opt/codex-primer/scripts/prime.sh` 中可调整：

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `MODEL` | `gpt-5.6-luna` | Codex 模型 |
| `PROMPT` | `Reply with exactly: OK` | 测试提示词 |
| `TIMEOUT_SECONDS` | `180` | 单次超时（秒） |
| `MAX_ATTEMPTS` | `2` | 最大尝试次数 |
| `RETRY_DELAY_SECONDS` | `30` | 重试间隔（秒） |

执行时间在 `/etc/systemd/system/codex-primer.timer` 的 `OnCalendar` 中配置，修改后执行 `systemctl daemon-reload && systemctl restart codex-primer.timer`。

## 启动

```bash
systemctl daemon-reload
systemctl enable --now codex-primer.timer
systemctl list-timers --all | grep codex-primer
```

## 手动测试

```bash
/opt/codex-primer/scripts/prime.sh manual
echo "exit=$?"
cat /opt/codex-primer/state/latest.json
```

运行完成后会自动发送 Bark，无需另外执行通知脚本。

## 查看运行结果

```bash
# 最近一次执行状态
cat /opt/codex-primer/state/latest.json

# 历史日志
ls -lt /opt/codex-primer/state/history/ | head

# 定时器状态
systemctl status codex-primer.timer

# systemd 调度日志
journalctl -u codex-primer-dispatch.service -n 50 --no-pager
```

## 更新

在现有部署上更新脚本：

```bash
cd /opt/codex-primer-repo
git pull --ff-only origin main

cp scripts/prime.sh scripts/check-result.sh /opt/codex-primer/scripts/
chmod 700 /opt/codex-primer/scripts/*.sh

cp systemd/codex-primer.timer \
   systemd/codex-primer-dispatch.service \
   systemd/codex-primer@.service \
   /etc/systemd/system/

systemctl daemon-reload
systemctl restart codex-primer.timer
```

更新时保留服务器上的 `codex-home/auth.json`、`config/notify.env` 及 `state/`，不要用仓库文件覆盖它们。

## 停止

```bash
systemctl disable --now codex-primer.timer
```

## 安全

不要提交以下运行时文件：

- `codex-home/auth.json`
- `config/notify.env`
- `state/`、`logs/`、`run/`

`.gitignore` 已包含相关忽略规则。公开仓库前仍应检查 Git 提交历史。
