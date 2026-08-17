# Troubleshooting

## Mac Agent

### Agent 拒绝启动

确认 `agent/.env` 里有至少 24 位 URL-safe 随机 `WATCH_TOKEN`，且不是 `change-me-to-a-long-random-token`、`replace-with-a-long-random-token` 等示例占位值。

推荐重新生成：

```bash
scripts/bootstrap-local.sh --lan
```

### `/watch` 返回 401

iPhone App 和 curl 请求必须发送 `agent/.env` 里的同一个 `WATCH_TOKEN`。

```bash
curl -H "x-watch-token: <token>" http://127.0.0.1:8787/watch
```

### iPhone 连不上 Mac Agent

检查：

- iPhone 和 Mac 是否在同一个可信 Wi-Fi。
- `AGENT_HOST=0.0.0.0` 是否已用于局域网测试。
- iPhone App 使用的是 `http://<Mac-LAN-IP>:8787`，不是 `127.0.0.1`。
- macOS 防火墙、VPN 或公司网络策略是否拦截局域网访问。

查 Mac Wi-Fi IP：

```bash
ipconfig getifaddr en0
```

### Tailscale URL 连不上

检查：

- Mac 和 iPhone 是否在同一个 tailnet。
- iPhone 上 Tailscale VPN 是否已连接。
- Mac Agent 是否仍在运行，且 `AGENT_HOST=127.0.0.1`。
- `tailscale serve 8787` 是否仍在前台运行。
- iPhone App 的 URL 是否使用 Tailscale Serve 显示的 `https://...ts.net` 地址。
- 没有误用 Tailscale Funnel。

### Codex 额度缺失

直接测试 Codex adapter：

```bash
cd agent
source .venv/bin/activate
codex-quota-app-server --raw
codex-quota-app-server
```

如果失败，确认本机 `codex` 命令已安装且已登录。

`codex-quota-app-server` 正常返回时会写入短期本地 cache。首次真机安装后，
如果 iPhone / Watch 还显示 Codex `error`，可以先预热一次：

```bash
cd agent
source .venv/bin/activate
codex-quota-app-server >/dev/null
```

如果这两个命令能返回 quota，但 iPhone / Watch 仍显示 Codex `error`，继续测试 Mac Agent：

```bash
scripts/doctor.sh
```

关注输出里的 provider 摘要：

```text
codex: status=error source=...
```

常见情况：

- `source=CODEX_QUOTA_COMMAND` 且错误包含 `timed out waiting for JSON-RPC id=0`：Codex app-server 初始化没有及时返回。先关闭重复测试造成的残留 helper，再重启 Mac Agent。
- `/watch` 请求超时，但 `/health` 正常：Mac Agent 正在等待 Codex adapter。等 1 分钟再试，或先单独运行 `codex-quota-app-server` 预热。
- `source=CODEX_QUOTA_COMMAND cache` 且 `status=ok`：Agent 使用最近一次成功的 Codex adapter 结果兜底，可以回到 iPhone 点 `Fetch & Sync to Watch`。
- Watch 或 iPhone 显示 `codex_quota_command error`：先不要重装 App。按顺序跑 `codex-quota-app-server`、`scripts/doctor.sh`、再在 iPhone 点 `Fetch & Sync to Watch`。如果 adapter 单独正常而 App 仍报错，记录 provider 的 `status/source/error` 脱敏摘要再复测。
- 单独 adapter 正常、`/watch` 仍失败：记录为 Agent 路径复现问题，保留脱敏错误摘要，第二轮真机测试时复查。

可以按需调大/调小这些本机参数：

```text
CODEX_APP_SERVER_TIMEOUT_SECONDS=12
QUOTA_PROVIDER_TIMEOUT_SECONDS=16
QUOTA_CACHE_MAX_AGE_SECONDS=1800
```

只记录 `status/source/error` 摘要，不粘贴完整 `/watch` payload，不公开 `WATCH_TOKEN`。

## iPhone 和 Apple Watch

### Watch App 没出现

确认 iPhone 和 Apple Watch 已配对并连接，然后从 Xcode 运行 iPhone target。Watch App 安装可能需要一点时间。

如果 iPhone 上已经有 `Codex Quota`，但 Watch 上一直没有，通常是 companion Watch App 没有自动下发。先确认 Watch 能被 Xcode 看到：

```bash
xcrun devicectl list devices
```

如果你用教程里的 `/tmp/coding-quota-derived-data` 构建过，可以直接安装到手表：

```bash
xcrun devicectl device install app \
  --device <你的 Apple Watch device id> \
  "/tmp/coding-quota-derived-data/Build/Products/Debug-iphoneos/CodingQuota.app/Watch/CodingQuota Watch App.app"
```

然后解锁 Apple Watch，在手表 app 列表里打开 `Codex Quota`。如果启动命令报 `Can't launch when device is locked`，不是安装失败，是手表还锁着。

### Watch App 显示旧数据

打开 iPhone App，点击 `Fetch & Sync to Watch`。Watch App 打开时会先尝试直连 Mac Agent；如果 Watch 不在同一局域网、Tailscale/VPN 未连接，或 Mac Agent URL 不可达，就会回退为请求 iPhone 刷新并继续显示最后一次快照。

Watch 页面底部会显示最近一次刷新路径：

| 显示 | 含义 |
|---|---|
| `direct ok` | Watch 直接访问 Mac Agent 成功 |
| `iphone` | Watch 使用 iPhone 中继同步到最新快照 |
| `cached` | 正在显示本地保存的上次快照 |
| `no config` | Watch 还没收到 Mac URL/token 配置，先在 iPhone 扫码并 Fetch |
| `direct -1004` | Watch 直连 Mac Agent 连接失败，常见于 Mac Agent 未监听局域网 URL 或网络不可达 |
| `direct -1009` | Watch 当前网络不可达，检查 Wi-Fi/Tailscale/VPN |
| `direct failed` | Watch 直连失败但错误无法细分，继续看 iPhone 是否能 Fetch |
| `stale / ...` | 快照超过 15 分钟，但仍显示最后一次数据 |
| `old / ...` | 快照超过 2 小时，先打开 iPhone App 重新 Fetch |

看到 `iphone` 不是错误。它表示这一次最新数据来自 iPhone bridge；只要数据更新且 Mac Agent 日志有 `/watch 200`，第二路刷新就是正常的。

### Watch App 没有立即更新

Watch App 打开时的直连刷新使用短超时，失败后才走 iPhone/WatchConnectivity。若 iPhone 也不可达 Mac Agent，Watch 会继续显示最后一次快照。

iPhone 手动 Fetch 默认等待 `/watch` 最多 20 秒。首次 Codex app-server 冷启动可能仍然慢；先在 Mac 上运行 `codex-quota-app-server >/dev/null` 预热，或者等 Agent cache 生成后再回到 iPhone 点击 `Fetch & Sync to Watch`。

### 签名失败

使用自己的 Apple Team 和 Bundle ID。仓库里的 ID 都是占位值：

```text
com.example.CodexQuota
com.example.CodexQuota.watchkitapp
group.com.example.CodexQuota
```

如果账号暂时不支持 App Groups，第一次真机安装可以先不启用 App Groups。WatchConnectivity 仍可完成 iPhone 到 Watch 的同步。

## 公开前

公开 fork 或 issue 前先跑：

```bash
scripts/check-public-ready.sh --worktree
```

不要推送本地 handoff、ignored files、真实 token、签名文件或所有分支。
