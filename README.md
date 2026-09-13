# Codex Primer

用于在固定时段自动调用一次 Codex，并在数分钟后通过 Bark 推送执行结果。

## 功能

- 按北京时间每天 4 个时段自动执行 Codex：07:00、12:05、17:10、22:15
- 每次执行 5 分钟后检查结果并通过 Bark 推送
- 使用 `gpt-5.6-luna`
- 保存每次运行日志与 JSON 状态
- 使用 `flock` 防止重复执行
- systemd timer 驱动，VPS 系统时区无需改成北京时间

## 目录

运行时目录：

```text
/opt/codex-primer/
├── codex-home/
│   ├── auth.json          # Codex 登录凭证，不提交 Git
│   └── config.toml
├── scripts/
│   ├── prime.sh
│   └── check-result.sh
├── state/
│   ├── latest.json
│   └── history/
├── logs/
├── run/
└── config/
    └── notify.env         # Bark 密钥，不提交 Git
```

systemd 文件安装到：

```text
/etc/systemd/system/
```

## 仓库结构

```text
.
├── README.md
├── .gitignore
├── config/
│   ├── config.toml
│   └── notify.env.example
├── scripts/
│   ├── prime.sh
│   └── check-result.sh
└── systemd/
    ├── codex-primer@.service
    ├── codex-primer-check@.service
    ├── codex-primer-dispatch.service
    ├── codex-primer-check-dispatch.service
    ├── codex-primer.timer
    └── codex-primer-check.timer
```

## 安装

```bash
mkdir -p /opt/codex-primer/{codex-home,scripts,state/history,logs,run,config}

cp scripts/prime.sh /opt/codex-primer/scripts/
cp scripts/check-result.sh /opt/codex-primer/scripts/
cp config/config.toml /opt/codex-primer/codex-home/config.toml

chmod 700 /opt/codex-primer/scripts/*.sh
chmod 700 /opt/codex-primer/codex-home /opt/codex-primer/config
```

配置 Bark：

```bash
cp config/notify.env.example /opt/codex-primer/config/notify.env
chmod 600 /opt/codex-primer/config/notify.env
```

然后编辑：

```text
BARK_SERVER="https://api.day.app"
BARK_KEY="你的 Bark Key"
```

## Codex 登录

推荐直接在独立的 `CODEX_HOME` 下登录：

```bash
CODEX_HOME=/opt/codex-primer/codex-home codex login --device-auth
```

检查：

```bash
CODEX_HOME=/opt/codex-primer/codex-home codex login status
```

成功时应看到：

```text
Logged in using ChatGPT
```

注意：`auth.json` 包含敏感登录凭证，禁止提交 Git。

## 安装 systemd

```bash
cp systemd/* /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now codex-primer.timer
systemctl enable --now codex-primer-check.timer
```

查看定时任务：

```bash
systemctl list-timers --all | grep codex-primer
```

## 手工测试

只执行 Codex：

```bash
/opt/codex-primer/scripts/prime.sh manual
cat /opt/codex-primer/state/latest.json
```

执行 Codex 后立即测试 Bark：

```bash
/opt/codex-primer/scripts/prime.sh manual && \
/opt/codex-primer/scripts/check-result.sh manual
```

成功状态示例：

```json
{
  "model": "gpt-5.6-luna",
  "exit_code": 0,
  "result": "success"
}
```

## 常见故障

### exit_code=124

`124` 是 GNU `timeout` 的超时返回码。本项目当前 Codex 超时时间为 180 秒。

如果日志只出现：

```text
Reading additional input from stdin...
```

说明 Codex CLI 可能卡在 stdin 读取。

可以手工验证：

```bash
printf '%s\n' 'Reply with exactly: OK' | \
CODEX_HOME=/opt/codex-primer/codex-home \
timeout 30 codex -m gpt-5.6-luna exec --skip-git-repo-check -
```

### 401 Unauthorized

如果出现：

```text
Missing bearer or basic authentication in header
```

通常需要重新登录独立的 Codex Home：

```bash
CODEX_HOME=/opt/codex-primer/codex-home codex logout
CODEX_HOME=/opt/codex-primer/codex-home codex login --device-auth
```

随后再次手工测试。

### bubblewrap warning

如果提示系统 PATH 找不到 bubblewrap，但同时显示 Codex 会使用 bundled bubblewrap，且请求可以正常完成，则一般不是故障根因。

## 当前计划

北京时间：

```text
Codex   Bark 检查
07:00   07:05
12:05   12:10
17:10   17:15
22:15   22:20
```

## 已知注意事项

当前两个 timer 使用了：

```ini
Persistent=true
```

如果 VPS 在计划时间关机，重启后 systemd 可能补跑错过的任务。当前运行配置按原服务器真实文件保留；如不希望补跑，可后续将其改为 `Persistent=false` 或移除该配置，并给 dispatch 增加时段校验。

## 安全

以下内容不要提交：

- `/opt/codex-primer/codex-home/auth.json`
- `/opt/codex-primer/config/notify.env`
- `state/`
- `logs/`
- `run/`
- `*.bak-*`
