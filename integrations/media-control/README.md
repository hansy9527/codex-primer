# 媒体控制台集成（可选）

这部分保存已有媒体控制台的 Codex Primer 集成，不属于独立 Web 应用，默认 install.sh 不会安装它。

## 文件与运行位置

- primer-control.py：部署到 Primer 主机的 /usr/local/sbin/primer-control，沿用现有运行目录 /opt/codex-primer。
- static/primer.js：部署到控制台的 static/primer.js，依赖控制台现有的 api、authenticated、confirmClose、MediaTabs 和 DOM 辅助函数 $。
- console-schedule.patch：现有控制台 server.py 和 static/index.html 的增量补丁，只增加自动运行开关及对应 API。它以已集成 Primer 页签的控制台为基础，不是完整控制台源码；应用前应检查 git apply --check --unidiff-zero。
- test_primer_control.py：Linux 下运行 python3 -m unittest discover -s integrations/media-control -p 'test_*.py'。

## 开关行为

页面使用 role=switch 和 aria-checked 表达当前状态。打开页签首次读取状态，后续只在用户手动刷新或操作后更新，不使用定时刷新。

POST /media-control/api/primer/schedule 接收严格布尔值 enabled；继续使用控制台现有登录、Origin、CSRF 和请求体校验。请求经受限 SSH 调用 schedule on 或 schedule off，仅允许操作固定的 codex-primer.timer。

开启执行 systemctl enable --now codex-primer.timer；关闭执行 systemctl disable --now codex-primer.timer。关闭会跨重启保持，不会终止已经运行的模型任务，手动执行、失败重试和历史日志仍可用。定时器原有 Persistent=true 时，重新开启可能补执行错过的计划，以 systemd 的实际调度为准。

## 接入要求

SSH 账号必须使用专用密钥和强制命令包装器，将 SSH_ORIGINAL_COMMAND 原样作为单个参数交给 primer-control；不要开放 shell，不要拼接执行输入。网络地址、SSH 密钥、known_hosts 和控制台登录配置由部署方提供，不包含在本目录中。控制台后端的命令白名单和 Primer 主机上的 helper 必须一起升级。

升级前备份三个控制台文件及旧 helper，先部署 helper，再部署页面与 API，最后重启控制台。不要为部署本集成而运行 install.sh 或重装定时器，以免改变现有调度状态。升级不会替换 app.env、notify.env、Codex 登录凭证或历史记录。
