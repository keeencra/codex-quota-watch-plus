# 真机验收清单

目标：确认 Mac Agent、iPhone App、Apple Watch App 和 iPhone Widget 在真实设备上形成完整闭环。

不要在截图或日志里公开 `WATCH_TOKEN`、`agent/.env`、`~/.codex`、Apple Team ID、证书或描述文件。

## 1. Mac Agent

- 运行 `scripts/install-launch-agent.sh --lan`，或本机/Tailscale 模式按 `docs/setup.md` 配置。
- 运行 `scripts/doctor.sh`。
- 通过条件：
  - `agent/.env` 未被 git 跟踪。
  - `WATCH_TOKEN` 强度检查通过。
  - `/health` 有响应。
  - `/watch` 接受当前 token。
  - Codex 至少显示 `status/source`。
- 如果使用 launchd，重启 Mac 后再运行 `scripts/doctor.sh`，确认 LaunchAgent 已加载且 `/health` 正常。

## 2. Xcode 和签名

- 运行：

```bash
scripts/configure-ios-identifiers.sh --bundle-id com.yourname.CodexQuota
```

- 打开 `ios-watch/CodingQuota.xcodeproj`。
- 对三个 target 选择同一个 Apple Team：
  - `CodingQuota`
  - `CodingQuota Watch App`
  - `CodingQuotaWidgetExtension`
- 通过条件：
  - iPhone target 能安装到真机。
  - Watch App 随 iPhone App 安装到已配对 Apple Watch。
  - iPhone 主屏可添加 `Codex Quota` small / medium Widget。
  - 如果 Watch App 没有自动出现，能用 `xcrun devicectl device install app --device <Apple Watch device id> ".../CodingQuota Watch App.app"` 手动安装。
  - 如果 App Groups 不可用，先记录 limitation；WatchConnectivity 路径仍应可测。

## 3. iPhone 配对和拉取

- 在 Mac 上运行 `scripts/show-pairing-qr.sh --open-html`，用浏览器打开配对二维码。
- iPhone App 点击 `Scan Pairing QR` 扫码。
- 点击 `Fetch & Sync to Watch`。
- 通过条件：
  - Mac URL 自动填入。
  - token 不需要手动复制。
  - Diagnostics 里 Mac URL / Token 显示 `configured`。
  - Diagnostics 里 Watch 显示 `reachable` 或 `installed`。
  - iPhone App 显示最近同步时间。
  - Codex quota/status 能显示。
  - iPhone Widget 在下一次 WidgetKit reload 后显示同一份最近快照。

## 4. Apple Watch App

- 打开 Watch App `Codex Quota`。
- 通过条件：
  - Watch App 能看到最新 snapshot。
  - Watch 打开时会先尝试直连 Mac Agent；如果 Watch 或 iPhone 不可达 Mac Agent，应显示最后一次快照而不是空白。
  - Codex 页在有 5h/7d 两个 bucket 时能同时显示两个窗口；如果只有 5h，先用 `scripts/doctor.sh` 或 `codex-quota-app-server` 确认 Agent 是否真的返回 7d bucket。
  - Series 7 或小屏幕上文字不重叠，关键数字可读。

## 5. iPhone Widget

- 长按 iPhone 主屏，添加 `Codex Quota` Widget。
- 通过条件：
  - small Widget 显示 5h 剩余额度和刷新时间。
  - medium Widget 显示 5h / 7d、今日 token 和刷新时间。
  - Widget 不需要重新输入 Mac URL 或 token。
  - Widget 不发起实时网络请求；如果刚同步后没有立刻变化，等 iOS WidgetKit reload。

## 6. 离开局域网测试

如果配置 Tailscale：

- Mac Agent 继续监听 `127.0.0.1`。
- 使用 Tailscale Serve 暴露 tailnet 内 HTTPS URL。
- iPhone 连接 Tailscale VPN。
- iPhone App URL 改为 Tailscale Serve URL。
- 通过条件：
  - iPhone 不在家庭 Wi-Fi 时仍可 fetch。
  - 没有启用 Tailscale Funnel。

## 7. 记录结果

建议记录：

```text
Date:
Mac:
iPhone model / iOS:
Watch model / watchOS:
Network: LAN / Tailscale
Mac Agent: pass/fail
iPhone fetch: pass/fail
Watch App: pass/fail
Known limitations:
```

只记录状态和错误摘要，不粘贴真实 token、完整 `/watch` payload 或包含对话内容的截图。

## 7. 第二轮复测观察项

- 首次安装后 Watch App 可能显示 provider `error`，即使 iPhone/Watch 安装和配对都成功。
- 复测时区分三层：
  - Mac Agent `/health` 是否正常。
  - Mac Agent `/watch` 是否返回 Codex `status=ok`。
  - iPhone 点击 `Fetch & Sync to Watch` 后，Watch 是否显示同一份 snapshot。
- 如果 `/health` 正常但 `/watch` 的 Codex provider 是 `error`，先按 `docs/troubleshooting.md` 的“Codex 额度缺失”排查，不要把它归因到 Watch App 安装。
- 如果 `/watch` 报 `timed out waiting for JSON-RPC` 或 `codex_quota_command error`，先单独运行 `codex-quota-app-server`，确认本机 Codex quota adapter 能返回 JSON。
- 复测时确认 Watch 直连和 iPhone 中继都能工作：
  - Watch 与 Mac Agent 在同一可信局域网或私有 VPN 时，应能打开即刷新。
  - Watch 访问不到 Mac Agent 时，应能显示 iPhone 最近同步快照。
