# 远程访问与任务提醒设置

先按 README 安装 Mac Agent、iPhone、Apple Watch 并完成配对。公开版使用示例标识；运行 `scripts/configure-ios-identifiers.sh` 后，在 Xcode 为三个 Target 选择自己的 Team。该脚本同时更新 App Group 和手机／小组件共享 Keychain 标识。

## 1. 认证 HTTPS 网关

原 Mac Agent 监听 8787。新增网关仅监听 Mac 回环地址 8788，开放最小健康检查、带认证的 `/watch` 和 Bark 配置接口，不开放原始用量、调试和 API 文档。

在仓库的 `agent` 目录启动，沿用该目录的 `.env`：

```bash
.venv/bin/python -m codex_watch_agent.public_gateway
```

安装 ngrok 并在本机完成账号认证，使用自己账号分配的固定 HTTPS 域名，将隧道指向 **8788**：

```bash
ngrok http 8788 --url=https://YOUR-DOMAIN.ngrok-free.dev --inspect=false
```

认证信息通过 ngrok 自己的工具配置，不提交到仓库。然后在 iPhone Codex Quota 的 Mac Agent 地址栏填入这个 HTTPS 地址，保留已有配对 Token，点 Sync。所有服务需要在同一 Mac 用户下运行。不要将 8787 的完整 API 直接作为公开隧道目标。

手机和手表外出时可以通过互联网访问；Mac 仍需开机、联网且服务正在运行。该方案不是脱离 Mac 的云端额度采集。

## 2. Bark 通知

1. 安装 [Bark－给你的手机发推送](https://apps.apple.com/app/id1403753865)，开发者“丰 黄”。同名应用很多，请使用准确链接。
2. 打开 Bark，允许通知，复制首页以 `https://api.day.app/` 开头的推送地址。
3. 在 Codex Quota → 任务提醒粘贴地址并保存。此步骤要求上面的 HTTPS 网关可用。地址隐藏输入，保存后清空，不会回传到小组件或手表快照中。
4. 在 iPhone 的 Watch App → 通知中开启 Bark 镜像。
5. 在 `agent` 目录启动发送进程：

```bash
.venv/bin/python -m codex_watch_agent.task_events
```

推送使用固定的 `https://api.day.app/push`，默认为静音并保留通知显示。发送失败会重试，超过 15 分钟的待发提醒失效。HTTP 成功且 Bark 返回成功码，才记录为提交成功；实际设备收到通知仍需测试确认。

配置及任务数据库默认位于当前用户的 `~/Library/Application Support/CodexQuotaWatch`，权限仅限本用户。可通过 `CODEX_QUOTA_STATE_DIR` 指定目录，但 Hook、发送进程和网关必须设置相同目录。

## 3. Codex 任务事件

发送进程与 Hook 分离：Hook 只写本地队列，不联网、不自动批准操作、不要求继续回答。Hook 支持 `UserPromptSubmit`、`PermissionRequest`、`Stop`、`Interrupt`；结束一轮回复不表示整个项目已完成。

在 `agent` 目录运行以下命令生成与你的 Python 路径对应的配置示例：

```bash
.venv/bin/python - <<'PY'
import json, shlex, sys
command = shlex.quote(sys.executable) + ' -m codex_watch_agent.task_hook'
events = ['UserPromptSubmit', 'PermissionRequest', 'Stop', 'Interrupt']
print(json.dumps({'hooks': {event: [{'hooks': [{'type': 'command', 'command': command, 'timeout': 2}]}] for event in events}}, indent=2))
PY
```

将这些事件条目**合并**到当前用户的 `~/.codex/hooks.json`，保留已有 Hook。按 Codex 的 Hook 审查流程信任这四个命令，随后重启 Codex，再执行一个真实任务验证记录及结束提醒。不要绕过 Hook 信任检查。

上述两个 Python 进程和 ngrok 命令在前台运行，用于完成初始验证。长期使用时，为网关、通知进程和隧道分别配置 macOS 用户 LaunchAgent，使用绝对可执行文件路径、正确的 WorkingDirectory 和相同状态目录；可参考基础服务的 `scripts/install-launch-agent.sh`。本仓库不携带任何人的 LaunchAgent 实例、Bark 密钥或 ngrok 凭据。更新 Python 源码后需重新安装包并重启相应服务。

## 隐私与展示

- 通知只发送固定状态文字，不发送提示词、命令、工具参数、完整路径或助手回复。
- 本地任务记录包含项目目录名、内部摘要 ID、时间和状态；接口返回最近 10 个，手表显示最近 5 个。
- 小组件会独立请求额度；iOS 决定后台刷新频率，无法保证每分钟更新。
- 套餐标签来自实际接口数据。没有某个额度窗口时，不会将其他窗口复制为该窗口。

参考：[Codex Hooks](https://learn.chatgpt.com/docs/hooks)、[Bark API](https://github.com/Finb/bark-server/blob/master/docs/API_V2.md)。
