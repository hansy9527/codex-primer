# Codex Primer

使用 systemd 定时调用 Codex CLI，自动重试失败请求，并在最终结果产生后立即通过 Bark 推送通知。适用于 Linux VPS，无需持续运行桌面电脑。

> 本项目的定时调用仅验证 Codex 是否能够完成一个简短请求，不保证第三方服务的额度窗口或计费行为。请遵守服务提供方的使用条款。

## 功能与执行流程

- 北京时间（Asia/Shanghai）每天 **07:00、12:05、17:10、22:15** 启动一次
- 使用 `gpt-5.6-luna`，发送 `Reply with exactly: OK`，成功条件为退出码 0 且输出存在独立一行 `OK`
- 单次超时 180 秒，失败后等待 30 秒，**最多尝试 2 次**
- 最终写入 JSON 状态及每次尝试的独立日志，然后**立即调用 Bark**；不再等待第二个定时器
- Bark 报告成功或失败，失败时附带退出码、尝试次数、错误摘要与日志路径
- 使用 `flock` 防止同一时间重复运行
- Codex 执行结果与 Bark 发送结果分开处理：通知失败不会改变 Codex 的成功/失败判定

执行链：`codex-primer.timer → codex-primer-dispatch.service → codex-primer@<时段>.service → prime.sh → check-result.sh`

**注意：** 这是同一执行流程，不是数据库事务；Bark 发送失败可能导致未收到通知，需查看 VPS 日志。旧的 `codex-primer-check.timer` 已不再使用。

## 环境要求

- Linux + systemd、bash、`flock`、GNU `timeout`、Python 3、`curl`、Git
- Node.js / npm 和官方 Codex CLI（`@openai/codex`）
- 已有可用的 Codex 登录方式及 Bark 服务地址和 Key
- 服务器可以访问 Codex 所需的服务端接口

安装或升级 Codex CLI：

```bash
npm install -g @openai/codex@latest
codex --version
```

建议使用受支持的最新稳定版本。网络异常、模型权限或账号额度问题不能仅靠升级解决。

## 安装

本项目目前使用以下**固定路径**：

- Git 工作目录：`/opt/codex-primer-repo`
- 运行目录：`/opt/codex-primer`
- systemd 单元目录：`/etc/systemd/system`

以下示例适合**全新部署**，不要直接覆盖已有服务器的 `auth.json` 或 `notify.env`。

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

# 仅安装实际使用的三个 systemd 单元
cp systemd/codex-primer.timer \
   systemd/codex-primer-dispatch.service \
   systemd/codex-primer@.service \
   /etc/systemd/system/
```

### Codex 登录

```bash
CODEX_HOME=/opt/codex-primer/codex-home codex login --device-auth
CODEX_HOME=/opt/codex-primer/codex-home codex login status
```

登录凭证保存在本机 `/opt/codex-primer/codex-home/auth.json`，**不得上传到 GitHub**。

### Bark 配置

编辑 `/opt/codex-primer/config/notify.env`：

```bash
BARK_SERVER="https://api.day.app"
BARK_KEY="replace-with-your-bark-key"
```

使用你自己的 Key，并保持文件权限为 `600`。Bark 地址和 Key 只应存放在服务器本地，不要写入仓库或日志。

### 启动定时器

```bash
systemctl daemon-reload
systemctl enable --now codex-primer.timer

# 从旧版升级时停用独立 Bark 检查定时器，避免重复通知
systemctl disable --now codex-primer-check.timer 2>/dev/null || true

systemctl list-timers --all | grep codex-primer
```

`codex-primer@.service` 设置 `TimeoutStartSec=480`，覆盖两次 180 秒调用、30 秒重试间隔、通知发送及少量额外开销。

## 手动测试

```bash
/opt/codex-primer/scripts/prime.sh manual
echo "exit=$?"
cat /opt/codex-primer/state/latest.json
```

**执行 `prime.sh manual` 已经会自动发送 Bark**，不需要再调用 `check-result.sh`，否则会重复通知。一次完整失败测试可能耗时约 7 分钟。

查看最近一次手动执行的汇总日志：

```bash
tail -n 50 "$(ls -t /opt/codex-primer/state/history/*_manual.log | head -1)"
```

正常通知日志应包含 `Bark notification sent for slot manual`；若发送失败，汇总日志会记录 Bark 的错误退出码。

## 更新已有部署

在已经克隆到 `/opt/codex-primer-repo` 的服务器上：

```bash
cd /opt/codex-primer-repo
git pull --ff-only origin main

BACKUP="/opt/codex-primer/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp -a /opt/codex-primer/scripts/prime.sh /opt/codex-primer/scripts/check-result.sh "$BACKUP/"
cp -a /etc/systemd/system/codex-primer@.service "$BACKUP/"

bash -n scripts/prime.sh scripts/check-result.sh
cp scripts/prime.sh scripts/check-result.sh /opt/codex-primer/scripts/
chmod 700 /opt/codex-primer/scripts/*.sh
cp systemd/codex-primer@.service /etc/systemd/system/

systemctl disable --now codex-primer-check.timer 2>/dev/null || true
systemctl daemon-reload
systemctl restart codex-primer.timer
```

如果未来更新了主定时器或 dispatch 服务，也需要将对应的 `systemd/` 文件复制到 `/etc/systemd/system/` 并执行 `systemctl daemon-reload`。

**更新时不要覆盖**运行目录中的 `codex-home/auth.json`、`config/notify.env`、`state/`、`run/` 和 `logs/`。

## 状态与排障

- 最新状态：`/opt/codex-primer/state/latest.json`
- 历史 JSON、汇总日志及单次尝试日志：`/opt/codex-primer/state/history/`
- 主定时器：`systemctl status codex-primer.timer`
- 最近调度记录：`journalctl -u codex-primer-dispatch.service --no-pager -n 50`
- 具体实例：`journalctl -u 'codex-primer@12:05.service' --no-pager -n 50`

JSON 包含 `result`、`exit_code`、`attempts_used`、`max_attempts`、`failure_reason`、`attempts` 等字段。

常见问题：

- **退出码 124**：GNU `timeout` 中止了单次 Codex 调用；可检查对应 `_attemptN.log`
- **`failed to refresh available models`**：模型列表刷新异常；可能与 CLI、网络或服务端有关，不能单凭这一行断定根因
- **401 / Unauthorized**：检查 Codex 登录状态，必要时重新登录
- **Bark 没收到**：检查汇总日志、`notify.env`、Bark 服务连通性；Codex 成功不代表通知一定成功
- **`journalctl --since today` 没有记录**：服务器可能使用 UTC；北京时间早上 07:00 是前一天 UTC 23:00

## 安全与注意事项

- 不要提交 `codex-home/auth.json`、`config/notify.env`、历史状态、日志和备份；`.gitignore` 仅能防止未跟踪文件被意外添加，不能清除已经提交的历史
- 不要公开包含令牌、会话内容或敏感请求数据的原始日志
- 主定时器使用 `Persistent=true`：服务器关机错过执行时间后，重启可能补触发一次；dispatch 按**实际触发时的北京时间**确定时段，不一定是原计划时段
- 仓库保留了旧版 `codex-primer-check*` systemd 文件供参考，**当前部署不启用它们**
- 脚本中的模型、提示词、执行时刻、超时和重试参数目前为固定配置，修改后需重新部署对应文件

## License

当前仓库未附带许可证。若希望允许他人复制、修改和分发，请单独选择并添加适当的开源许可证。
