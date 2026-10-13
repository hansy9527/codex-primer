# Codex Primer

在 Linux VPS 上定时调用 Codex CLI，支持自定义每日执行时间、模型、超时与重试，并通过 Bark 推送成功或失败结果。

> 当前任务的成功条件是：Codex 退出码为 0，且输出包含独立一行 `OK`。默认提示词为 `Reply with exactly: OK`。本项目用于定时验证 Codex 调用是否正常，不是任意提示词的通用任务执行器。

## 1. 环境要求

- Linux + systemd（安装脚本需要 root 权限）
- Bash、Python 3（含 `zoneinfo` 时区数据）、Git、curl、`flock`、GNU `timeout`
- Node.js、npm 和 Codex CLI
- 可以使用 Codex 的账号，以及安装了 Bark 的 iPhone

安装或更新 Codex CLI：

```bash
npm install -g @openai/codex@latest
codex --version
```

确保服务器能访问 Codex 所需的登录和模型服务。

## 2. 获取项目并安装

```bash
git clone https://github.com/hansy9527/codex-primer.git
cd codex-primer
sudo bash install.sh /opt/codex-primer
```

省略安装目录时，默认也是 `/opt/codex-primer`。可指定其他绝对路径，例如：

```bash
sudo bash install.sh /data/my-codex
```

**仓库目录与安装目录是两个不同概念**：Git 仓库保存源码，安装目录保存实际运行脚本、配置、凭证、状态与日志。

安装程序会自动创建目录、初始化 `config/app.env` 和 `config/notify.env`（仅当不存在时）、生成 systemd 单元并启用定时器；**不需要手动设置 crontab 或 systemd timer**。重复安装不会覆盖已有配置和登录凭证。

**重要：安装完成就会启用定时器。** 首次部署时，如果还没配置登录和 Bark，建议先暂停：

```bash
sudo systemctl disable --now codex-primer.timer
```

完成下文的登录和通知测试后再启用。

## 3. Codex 登录配置（详细）

### 3.1 登录文件保存在哪里？

程序运行时使用独立的 Codex 配置目录：

```text
/opt/codex-primer/codex-home/
├── config.toml
└── auth.json         # 登录成功后由 Codex 生成；安装程序不创建
```

关键点：

- `auth.json` **不是单独一串 API Key**，不要自行猜测 JSON 结构，也不要把占位内容 `{}` 当作有效凭证。
- 安装脚本只创建 `codex-home` 目录，不会自动登录，也不会生成 `auth.json`。
- 必须让 Codex 在**相同的 `CODEX_HOME` 目录**中完成登录，否则定时任务可能找不到凭证。
- 当前 systemd 服务以 `root` 身份运行；使用其他 Linux 用户登录产生的默认 `~/.codex/auth.json` 不会自动被此项目读取。

### 3.2 推荐：设备码登录（适合无桌面的 VPS）

在服务器上执行：

```bash
sudo env CODEX_HOME=/opt/codex-primer/codex-home codex login --device-auth
```

根据终端提示，在你自己的电脑或手机浏览器打开 Codex 提供的登录页面，输入设备码并完成账号授权。**设备码、登录页面地址以终端当次提示为准**。

登录完成后检查状态：

```bash
sudo env CODEX_HOME=/opt/codex-primer/codex-home codex login status
```

如果设备码登录不可用，先查看当前 CLI 支持的方式：

```bash
codex login --help
```

然后按官方支持的方式登录，但仍需确保使用上述 `CODEX_HOME`。

### 3.3 已经在其他环境登录过？

可以使用 Codex 自身的登录流程在新 VPS 上重新授权。若确需迁移已有的有效 `auth.json`，请通过可信的加密通道传输，并确保最终路径为：

```text
/opt/codex-primer/codex-home/auth.json
```

然后设置权限：

```bash
sudo chmod 700 /opt/codex-primer/codex-home
sudo chmod 600 /opt/codex-primer/codex-home/auth.json
```

不要将凭证上传到 GitHub、聊天记录或公开网盘，也不要把 `auth.json` 的内容贴到 Issue 中。

### 3.4 验证 Codex 是否可用

先检查登录状态：

```bash
sudo env CODEX_HOME=/opt/codex-primer/codex-home codex login status
```

再使用项目的实际执行脚本进行测试（会调用模型并消耗相应额度）：

```bash
sudo /opt/codex-primer/scripts/prime.sh manual
```

测试日志会保存在 `/opt/codex-primer/state/history/`。首次测试前，建议先完成下一节 Bark 配置，以便同时验证通知。

## 4. Bark 推送配置（详细）

### 4.1 获取 Bark Key

1. 在 iPhone 安装并打开 **Bark** 应用，允许通知权限。
2. 在 Bark 中找到应用显示的推送地址，通常类似 `https://api.day.app/你的设备Key/`；如果使用自建 Bark 服务，则使用自建服务地址。
3. 将地址拆成 **服务器地址** 和 **Key** 两部分，分别填入配置文件。

例如，假设 Bark 显示的地址为：

```text
https://api.day.app/EXAMPLE_DEVICE_KEY/
```

则配置为：

```ini
BARK_SERVER="https://api.day.app"
BARK_KEY="EXAMPLE_DEVICE_KEY"
```

上面的 `EXAMPLE_DEVICE_KEY` 仅为示例，不能直接使用。真实 Key 应从**你自己的 Bark 应用**中获取。

### 4.2 编辑配置文件

安装时若文件不存在，会自动从模板创建：

```text
/opt/codex-primer/config/notify.env
```

编辑：

```bash
sudo nano /opt/codex-primer/config/notify.env
```

内容格式：

```ini
BARK_SERVER="https://api.day.app"
BARK_KEY="替换为自己的真实Key"
```

保存后限制访问权限：

```bash
sudo chmod 600 /opt/codex-primer/config/notify.env
```

**不要把完整 Bark 推送地址或真实 Key 提交到仓库，也不要在公开终端截图中展示。**

### 4.3 单独测试 Bark

下面的命令会读取已有配置，发送一条测试通知，不会调用 Codex，也不会在命令行打印 Key：

```bash
sudo bash -c '
  set -euo pipefail
  source /opt/codex-primer/config/notify.env
  curl -fsS --connect-timeout 10 --max-time 25 \
    --get --data-urlencode "title=Codex Primer 测试" \
    --data-urlencode "body=Bark 配置成功" \
    "${BARK_SERVER%/}/${BARK_KEY}/"
  echo
'
```

手机收到“Codex Primer 测试”即表示 Bark 基本连通。若没有收到，先检查 iPhone 的通知权限、网络、Key 是否完整以及 `BARK_SERVER` 是否正确。**Bark Key 应视为秘密凭证。**

### 4.4 完整联调

登录和 Bark 都配置完成后，执行：

```bash
sudo /opt/codex-primer/scripts/prime.sh manual
echo "exit=$?"
```

查看结果：

```bash
sudo cat /opt/codex-primer/state/latest.json
```

正常情况下，`result` 为 `success`，Codex 返回 `OK`，Bark 收到成功通知。注意模型调用可能需要几十秒或更久；即使 Codex 调用成功，Bark 也可能因网络或配置问题单独发送失败。

## 5. 设置执行时间、模型和重试

编辑：

```bash
sudo nano /opt/codex-primer/config/app.env
```

默认配置：

```ini
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
| `APP_TZ` | 时区，例如 `Asia/Shanghai` |
| `SCHEDULE_TIMES` | 每日时间，空格分隔，支持任意正整数个不重复的 `HH:MM` |
| `MODEL` | Codex CLI 调用的模型，必须是当前账号和 CLI 可用的模型 |
| `PROMPT` | 调用提示词；当前成功判定依赖独立一行 `OK` |
| `TIMEOUT_SECONDS` | 每次尝试的最长秒数 |
| `MAX_ATTEMPTS` | 最大尝试次数（包含首次） |
| `RETRY_DELAY_SECONDS` | 两次尝试之间的等待秒数 |

例如每天六次：

```ini
SCHEDULE_TIMES="06:00 09:30 12:00 15:45 19:00 23:30"
```

**修改 `app.env` 后，需要重新运行安装脚本**，让 systemd 的时间表与超时参数同步更新：

```bash
cd /path/to/your/codex-primer-repository
sudo bash install.sh /opt/codex-primer
```

将 `/path/to/your/codex-primer-repository` 换成实际 Git 克隆目录。如果此前为了初始化关闭了定时器，上述安装命令也会重新启用它。

## 6. 查看运行状态和日志

```bash
systemctl is-enabled codex-primer.timer
systemctl is-active codex-primer.timer
systemctl list-timers --all codex-primer.timer
journalctl -u codex-primer-dispatch.service -n 50 --no-pager
ls -lt /opt/codex-primer/state/history/ | head
```

- `enabled` 表示定时器设置为开机启用。
- `active` 表示定时器当前正在等待触发。
- `state/latest.json` 保存最近一次执行结果；`state/history/` 保存历史结果和尝试日志。
- 服务器显示 UTC 时间不一定是错误；定时器中的 `Asia/Shanghai` 时间会换算为 UTC 展示。
- 刚安装完成、尚未到达首次触发时间时，调度日志可能为空。

暂停任务：

```bash
sudo systemctl disable --now codex-primer.timer
```

重新启用：

```bash
sudo systemctl enable --now codex-primer.timer
```

## 7. 更新程序

```bash
cd /path/to/your/codex-primer-repository
git pull --ff-only
sudo bash install.sh /opt/codex-primer
```

更新前建议备份运行目录中的配置及凭证，并确认没有任务正在执行。安装脚本不会覆盖已有的 `app.env`、`notify.env`、`auth.json`。

## 8. 常见问题

**安装后还要手动创建定时任务吗？** 不需要，`install.sh` 会生成并启用 systemd timer。

**为什么 `auth.json` 不存在？** 安装程序不生成登录凭证。请用 `CODEX_HOME=/安装目录/codex-home codex login --device-auth` 完成登录。

**为什么已经登录了，定时执行仍提示未登录？** 检查登录时使用的 `CODEX_HOME` 是否与项目运行目录一致；不要误用普通用户默认的 `~/.codex`。

**为什么没有收到 Bark？** 先用第 4.3 节的命令单独测试推送，再检查通知权限、服务器地址和 Key。

**能在同一台机器安装两套独立实例吗？** 当前 systemd 单元名称固定为 `codex-primer.*`，因此不支持两套独立实例同时管理；指定另一个安装目录会替换 systemd 对应的运行路径。

**可以把 `auth.json` 和 `notify.env` 提交到 GitHub 吗？** 不可以。这些文件包含敏感凭证，必须只保存在可信环境中。仓库已配置相关 `.gitignore`，但仍应在提交前人工检查。
