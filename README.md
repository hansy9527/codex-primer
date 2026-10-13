# Codex Primer

Linux VPS 上的 Codex CLI 定时执行工具：按自定义时间调用模型，失败自动重试，并通过 Bark 推送最终结果。

## 环境要求

- Linux + systemd、Bash、Python 3、Git、curl、flock、GNU timeout
- Node.js、npm、Codex CLI
- 可用的 Codex 登录账号和 Bark Key

```bash
npm install -g @openai/codex@latest
```

## 安装

```bash
git clone https://github.com/hansy9527/codex-primer.git
cd codex-primer
sudo bash install.sh
```

默认运行目录为 `/opt/codex-primer`。也可以在安装时指定其他**绝对路径**：

```bash
sudo bash install.sh /data/codex-primer
```

运行目录和 Git 克隆目录可以不同。下面用 `/opt/codex-primer` 举例；使用自定义目录时，请将示例中的路径替换为实际路径。

安装程序会生成 systemd 单元、创建运行目录，并在首次安装时生成 `config/app.env` 和 `config/notify.env`，再次安装不会覆盖已有配置。

## 配置

编辑 `/opt/codex-primer/config/app.env`：

```bash
APP_TZ="Asia/Shanghai"
SCHEDULE_TIMES="07:00 12:05 17:10 22:15"
MODEL="gpt-5.6-luna"
PROMPT="Reply with exactly: OK"
TIMEOUT_SECONDS=180
MAX_ATTEMPTS=2
RETRY_DELAY_SECONDS=30
```

| 配置项 | 说明 |
| --- | --- |
| `APP_TZ` | 时区，如 `Asia/Shanghai` |
| `SCHEDULE_TIMES` | 每天执行的时间，空格分隔，**不限于 4 个**；例如 `08:00 20:30` |
| `MODEL` | Codex CLI 使用的模型 |
| `PROMPT` | 发给 Codex 的测试提示词 |
| `TIMEOUT_SECONDS` | 每次尝试的超时秒数 |
| `MAX_ATTEMPTS` | 最大尝试次数，包含首次执行 |
| `RETRY_DELAY_SECONDS` | 失败后的重试等待秒数 |

提示：当前脚本以 Codex 输出包含**独立一行 `OK`**且退出码为 0 作为成功标准；修改 `PROMPT` 时请保留该约定。

时间可以任意增减，例如每天一次 `SCHEDULE_TIMES="09:00"`，或每天六次 `SCHEDULE_TIMES="06:00 09:00 12:00 15:00 18:00 21:00"`。时间必须为 24 小时制的 `HH:MM`，不能重复。

编辑 Bark 配置 `/opt/codex-primer/config/notify.env`：

```bash
BARK_SERVER="https://api.day.app"
BARK_KEY="replace-with-your-bark-key"
```

配置 Codex 登录：

```bash
CODEX_HOME=/opt/codex-primer/codex-home codex login --device-auth
CODEX_HOME=/opt/codex-primer/codex-home codex login status
```

**修改 `app.env` 后，必须重新运行安装脚本**，以重新生成 systemd 时间表并计算服务超时：

```bash
cd codex-primer
sudo bash install.sh /opt/codex-primer
```

安装脚本会启用并重启定时器。不要把密钥写进 `app.env`；Bark Key 只放在 `notify.env` 中。

## 手动测试

```bash
/opt/codex-primer/scripts/prime.sh manual
echo "exit=$?"
cat /opt/codex-primer/state/latest.json
```

测试完成会自动发送 Bark，无需另外运行通知脚本。

## 查看任务

```bash
systemctl list-timers --all | grep codex-primer
systemctl status codex-primer.timer
journalctl -u codex-primer-dispatch.service -n 50 --no-pager
ls -lt /opt/codex-primer/state/history/ | head
```

运行状态保存在 `state/latest.json`，历史结果与每次尝试的日志保存在 `state/history/`。

## 更新

```bash
cd codex-primer
git pull --ff-only
sudo bash install.sh /opt/codex-primer
```

安装脚本不会覆盖已有的 `config/app.env`、`config/notify.env` 或 Codex 登录凭证。建议更新前自行备份运行目录。

## 停止

```bash
sudo systemctl disable --now codex-primer.timer
```

## 安全

`config/app.env`、`config/notify.env`、`codex-home/auth.json`、`state/`、`logs/` 和 `run/` 不应提交到 Git。仓库已设置对应的 `.gitignore` 规则。
