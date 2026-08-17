# 本机部署指南

目标：在自己的 Mac、iPhone、Apple Watch 上运行 Codex 额度监控。它不是一键安装包，也不会替你跳过 Apple 的签名和设备信任流程。

如果你熟悉 Xcode 真机调试，通常 30-60 分钟可以跑通第一版；如果第一次处理 Apple Watch target、App Group、局域网访问和签名，预留 1-2 小时更现实。

## 你需要准备

| 项目 | 必需 | 说明 |
|---|---:|---|
| Mac | 是 | 运行本地 Agent |
| iPhone + Apple Watch | 是 | iPhone 拉取数据并同步到手表 |
| Xcode | 是 | 安装 iPhone / Watch App |
| Python 3 | 是 | 运行 Mac Agent |
| Codex CLI/App 登录 | 建议 | Codex 额度读取需要 |

## 1. 安装 Mac Agent

```bash
git clone https://github.com/<owner>/codex-quota-watch.git
cd codex-quota-watch
scripts/bootstrap-local.sh --lan
```

脚本会创建 `agent/.venv`、安装 Mac Agent、生成 `agent/.env` 和随机 `WATCH_TOKEN`，并运行本地检查。只想先跑起来可以加 `--skip-checks`。

## 2. 常驻启动并测试 Agent

推荐用 macOS LaunchAgent 常驻运行 Mac Agent：

```bash
scripts/install-launch-agent.sh --lan
```

如果你之前已经手动开着 `codex-watch-agent`，先关掉那个前台进程；否则 8787 端口会被占用，安装脚本会停下来提示当前 listener。

这会复用 `scripts/bootstrap-local.sh` 完成本地安装，然后把服务注册到：

```text
~/Library/LaunchAgents/com.codingquota.agent.plist
```

Mac 登录后会自动启动 Agent；进程崩溃时 launchd 会重启它。查看状态和日志：

```bash
launchctl print gui/$(id -u)/com.codingquota.agent
tail -f ~/Library/Logs/com.codingquota.agent.out.log
tail -f ~/Library/Logs/com.codingquota.agent.err.log
```

停止常驻服务：

```bash
scripts/uninstall-launch-agent.sh
```

如果只是开发或临时排查，也可以手动前台启动：

```bash
cd agent
source .venv/bin/activate
codex-watch-agent
```

另开一个终端：

```bash
curl http://127.0.0.1:8787/health
curl -H "x-watch-token: <agent/.env 里的 WATCH_TOKEN>" http://127.0.0.1:8787/watch
```

查 Mac 局域网 IP：

```bash
ipconfig getifaddr en0
```

iPhone App 里填写：

推荐打开浏览器二维码配对：

```bash
scripts/show-pairing-qr.sh --open-html
```

如果当前环境不能自动打开浏览器，再用终端二维码备用：

```bash
scripts/show-pairing-qr.sh
```

也可以只生成 HTML 文件，然后用任意浏览器打开：

```bash
scripts/show-pairing-qr.sh --html /tmp/coding-quota-pair-qr.html
```

然后在 iPhone App 里点 `Scan Pairing QR`，扫浏览器页面里的二维码。二维码内容是本地配对 URI：

```text
llmquota://pair?url=<Mac-Agent-URL>&token=<WATCH_TOKEN>
```

App 只会接受 `llmquota://pair` 且 URL 为 `http` / `https` 的二维码。配对二维码包含 `WATCH_TOKEN`，不要发给别人或放到公开截图里。

扫码后：

- Mac URL 存在 App Group `UserDefaults`。
- `WATCH_TOKEN` 存在 iPhone Keychain。
- 旧版本如果已经把 token 存在 `UserDefaults`，新版会在首次打开或后台刷新时迁移到 Keychain 并清掉旧值。

如果不方便扫码，也可以手动填写：

```text
http://<Mac-LAN-IP>:8787
WATCH_TOKEN from agent/.env
```

`WATCH_TOKEN` 必须是至少 24 位 URL-safe 随机值。未设置、太短、包含非法字符或使用示例占位值时，Agent 会拒绝启动。

如果配对二维码截图或 token 泄露，轮换 token 并重新扫码：

```bash
scripts/rotate-watch-token.sh --restart-launch-agent
scripts/show-pairing-qr.sh --open-html
```

## 3. Xcode 签名和安装

如果你第一次用 Xcode 安装 iPhone + Apple Watch App，先看一遍
`docs/xcode-device-install.md`。Xcode 里的 project / target 名是
`CodingQuota`，但安装到 iPhone 和 Apple Watch 后显示的 App 名是
`Codex Quota`，这是正常的。

先把仓库里的示例标识改成你自己的。建议使用反向域名格式，例如 `com.yourname.CodexQuota`：

```bash
scripts/configure-ios-identifiers.sh --bundle-id com.yourname.CodexQuota
```

默认 App Group 会使用 `group.<bundle-id>`。如果你想手动指定：

```bash
scripts/configure-ios-identifiers.sh \
  --bundle-id com.yourname.CodexQuota \
  --app-group group.com.yourname.CodexQuota
```

这个脚本会同步 iPhone App、Watch App、iPhone Widget、App Group entitlement、Swift `AppConstants.appGroupID`、后台刷新任务 id，以及 Watch App 的 companion iPhone Bundle ID。

脚本不会替你配置 Apple Team、证书或设备信任，这些仍然要在 Xcode 里完成。

```bash
open ios-watch/CodingQuota.xcodeproj
```

### Xcode 最小操作路径

1. 打开项目后，左侧选择 `CodingQuota` project。
2. 依次点三个 target：
   - `CodingQuota`
   - `CodingQuota Watch App`
   - `CodingQuotaWidgetExtension`
3. 进入 `Signing & Capabilities`。
4. 三个 target 都选择同一个 Apple Team。
5. 确认 Bundle Identifier 已经从 `com.example...` 改成你自己的值。
6. 确认 App Groups 使用同一个 group，例如 `group.com.yourname.CodexQuota`。
7. 顶部运行设备选择你的 iPhone，不要选 Mac。
8. 点击 Run。第一次安装时，iPhone 可能要求 Trust、Developer Mode 或手动确认开发者证书。
9. iPhone App 安装成功后，Watch App 会随 companion app 安装到已配对 Apple Watch；如果没出现，稍等一会儿或在 Watch App 的 Installed on Apple Watch 里确认。

命令行检查需要 iOS simulator runtime。缺 runtime 时可安装：

```bash
xcodebuild -downloadPlatform iOS
```

真机安装不依赖 simulator runtime，但依赖 iPhone 连接、设备信任、Developer Mode 和签名配置。

在 Xcode 里检查三个 target：

```text
CodingQuota
CodingQuota Watch App
CodingQuotaWidgetExtension
```

每个 target 都需要：

- 选择自己的 Apple Team。
- 确认 Bundle ID 是刚才脚本写入的值。
- 如果账号支持 App Groups，三个 target 使用同一个 App Group；脚本已经写入 entitlement，但 Xcode 仍可能需要你在 Apple Developer 能力里确认。
- 如果暂时搞不定 App Groups，先跑 Watch App；iPhone 到 Watch 的同步主要靠 WatchConnectivity。

默认占位 ID：

```text
com.example.CodexQuota
com.example.CodexQuota.watchkitapp
group.com.example.CodexQuota
com.example.CodexQuota.widget
```

## 4. iPhone 和 Watch 同步

1. Xcode 里 Run iPhone target。
2. 打开 iPhone App。
3. 填 Mac URL 和 `WATCH_TOKEN`。
4. 点 `Fetch & Sync to Watch`。
5. 打开 Watch App `Codex Quota`。

完成后：

- Mac Agent 由 launchd 常驻，并且可以打开 `/health`。
- iPhone App 可以 fetch `/watch`。
- Apple Watch App 能看到最新同步快照。
- iPhone small / medium Widget 能显示最近一次成功同步的快照。
- 完整真机验收见 `docs/device-checklist.md`。

刷新机制的实际边界：

- Mac Agent：可以常驻后台，这是本项目应该保证的部分。
- iPhone App：打开时会按间隔自动刷新，也会注册 iOS background refresh；但 iOS 可能延迟或跳过后台任务。
- Watch App：打开时会先用配对配置直连 Mac Agent；如果 Watch 当时访问不到 Mac Agent，就回退为请求 iPhone 刷新和显示最后一次快照。
- iPhone Widget：只读 App Group 里的最近快照。iPhone App 成功 fetch 后会请求 WidgetKit 重新加载，但 iOS 可能合并或延迟，不保证实时。

Watch 直连只在 Watch 能访问 Mac Agent URL 时生效，例如同一可信局域网，或你自己配置了 Tailscale/VPN。离开局域网且没有私有网络通道时，Watch 仍能显示最近一次同步数据，但不能实时更新。

## 5. 可选：用 Tailscale 在外面看

如果希望离开家里的 Wi-Fi 后仍能从 iPhone 访问 Mac Agent，推荐使用 Tailscale Serve 把 tailnet 内请求转发到本机 `127.0.0.1:8787`。这样 Agent 仍只监听 localhost，不需要暴露公网端口。

前提：

- Mac 和 iPhone 都安装并登录同一个 Tailscale tailnet。
- iPhone 需要保持 Tailscale VPN 已连接。
- 仍然必须填写 `WATCH_TOKEN`。

Mac Agent 保持 localhost：

```bash
AGENT_HOST=127.0.0.1
codex-watch-agent
```

另开终端启用 Serve：

```bash
tailscale serve 8787
```

Tailscale 会显示一个只在 tailnet 内可访问的 HTTPS URL，形如：

```text
https://<mac-name>.<tailnet>.ts.net
```

iPhone App 里把 Mac Agent URL 改成这个 HTTPS URL，token 仍然填 `agent/.env` 里的 `WATCH_TOKEN`。

不要使用 Tailscale Funnel。Funnel 是公网入口，不符合本项目“本机/私有网络使用”的默认安全边界。

参考：

- https://tailscale.com/docs/features/tailscale-serve
- https://tailscale.com/docs/reference/tailscale-cli

## 6. 让本机 Codex 帮你部署

在仓库根目录运行：

```bash
cp AGENTS.example.md AGENTS.md
```

然后把 `docs/codex-deploy-prompt.md` 的内容交给本机 Codex App / Codex CLI。Codex 可以自动创建 Python 环境、生成 token、运行检查和诊断；不能替你完成 Apple 账号签名、设备信任、Watch 配对或系统后台刷新限制。

如果你想直接复制，可以使用下面的精简版：

```text
你是我的本机部署助手。请在当前仓库部署 Apple Watch Codex 额度监控。

目标：
1. 不上传、不提交、不打印真实 WATCH_TOKEN、~/.codex、auth 文件、cookies、Apple 签名文件。
2. 使用本地脚本完成 Mac Agent 安装、.env 生成、检查和诊断。
3. 只在我的 Mac 本地或可信局域网运行，不暴露公网。
4. 如果 Xcode 签名需要我手动选择 Team、Bundle ID、App Group，请停下来告诉我具体点哪里。

请执行：
1. 读取 README.md、docs/setup.md、docs/troubleshooting.md。
2. 运行 scripts/install-launch-agent.sh --lan。
3. 运行 scripts/show-pairing-qr.sh --open-html，让浏览器直接打开配对二维码；如果不能自动打开浏览器，再运行 scripts/show-pairing-qr.sh。确认二维码出现；不要打印真实 WATCH_TOKEN。
4. 运行 scripts/doctor.sh。
5. 如果 Mac Agent 没有启动，请报告 launchctl 状态和日志路径，不要打印真实 WATCH_TOKEN。
6. 最后报告 agent/.venv、agent/.env、/health、/watch 测试命令、iPhone URL、配对二维码命令、WATCH_TOKEN 文件位置、Xcode 手动步骤、Watch 同步方式。
```

## 7. 一键体检

```bash
scripts/doctor.sh
```

它会检查本机命令、`agent/.env` 是否被 git 跟踪、`.env` 权限、`WATCH_TOKEN` 强度、LaunchAgent 状态、Mac Agent `/health` 和 `/watch`，以及当前 git 状态。脚本不会打印真实 `WATCH_TOKEN`。

## 不要做

- 不要把 `WATCH_TOKEN`、`agent/.env`、`~/.codex` 发到网上。
- 不要把 Mac Agent 暴露到公网。
- 不要把真实 Apple Team ID、证书、描述文件提交到仓库。
