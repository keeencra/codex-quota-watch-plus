# 复制给 Codex 的本机部署 Prompt

把下面整段复制给本机 Codex App / Codex CLI。它适合第一次部署，也适合出错后让 Codex 帮你按项目文档排查。

```text
你是我的本机部署助手。请在当前仓库部署 Codex Quota Apple Watch 额度监控。

目标：
1. 在我的 Mac 本地安装并启动 Mac Agent。
2. 生成安全的 WATCH_TOKEN，但不要把真实 token 打印到最终回答里。
3. 用二维码把 Mac URL + WATCH_TOKEN 配对到 iPhone App。
4. 帮我确认 Xcode 项目能安装到 iPhone / Apple Watch，遇到签名或设备信任步骤时停下来告诉我具体点哪里。

安全边界：
1. 不上传、不提交、不打印真实 WATCH_TOKEN、agent/.env、~/.codex、auth 文件、cookies、Apple Team ID、签名证书或 provisioning profile。
2. 不把 Mac Agent 暴露到公网；默认只用本机或可信局域网。需要外网访问时，只使用 Tailscale 私有 tailnet，不启用 Funnel。
3. 不修改 GitHub 公开状态、不 push、不发布 release，除非我单独明确要求。

请按顺序执行：
1. 读取 README.md、docs/setup.md、docs/xcode-device-install.md、docs/troubleshooting.md、docs/device-checklist.md。
2. 运行 git status，确认有没有未提交或未跟踪文件；不要删除用户文件。
3. 运行 scripts/install-launch-agent.sh --lan。
4. 运行 scripts/doctor.sh。
5. 运行 scripts/show-pairing-qr.sh --open-html，让浏览器直接打开配对二维码；如果不能自动打开浏览器，再运行 scripts/show-pairing-qr.sh。确认二维码出现；不要在最终回答里贴出二维码内容或真实 token。
6. 如果 Mac Agent 启动失败，报告 launchctl 状态、日志路径和脱敏错误摘要。
7. 如果 /health 或 /watch 失败，报告命令、HTTP 状态和脱敏错误摘要。
8. 运行 scripts/configure-ios-identifiers.sh --bundle-id com.<我的名字>.CodexQuota 前，先问我要真实 Bundle ID；不要自己猜。
9. 打开 ios-watch/CodingQuota.xcodeproj 前，检查 Xcode 环境：
   - xcodebuild -showsdks 是否有 iPhoneOS 和 WatchOS SDK。
   - xcrun simctl list runtimes 是否有对应 watchOS runtime。
   - xcodebuild -project ios-watch/CodingQuota.xcodeproj -scheme CodingQuota -showdestinations 是否能看到我的 iPhone。
10. 如果 Xcode 报 watchOS platform/runtime 缺失，先告诉我需要在 Xcode > Settings... > Components 安装对应 watchOS platform。只有我明确同意时，才运行可能接近 4GB 的 xcodebuild -downloadPlatform watchOS。
11. 打开 ios-watch/CodingQuota.xcodeproj 后，告诉我三个 target 都要选同一个 Apple Team：
   - CodingQuota
   - CodingQuota Watch App
   - CodingQuotaWidgetExtension
12. 如果 Xcode 报 No Account for Team、No profiles were found、需要 Apple ID 登录、iPhone Trust、Developer Mode、Personal Team、App Group、重新配对 Watch，请停下来给我具体操作，不要伪造安装成功。
13. 如果需要命令行真机 build，用 /tmp 或系统 DerivedData 路径，不要把 DerivedData 写进仓库。
14. 真机安装后，指导我在 iPhone App 扫码、点击 Fetch & Sync to Watch、打开 Watch App，并添加 iPhone small / medium Widget 验证最近快照。
15. 最后运行 scripts/check-public-ready.sh --worktree，并报告通过项和任何剩余限制。

最终回答请包含：
1. Mac Agent 是否已安装并常驻。
2. /health 和 /watch 是否通过。
3. iPhone App 应填写或扫码得到的 Mac URL 是否已确认。
4. WATCH_TOKEN 存放位置，只说 agent/.env，不打印值。
5. Xcode 还需要我手动完成哪些步骤，包括 Apple ID、Team、platform/runtime、设备信任和 provisioning。
6. Watch App 的真实刷新限制。
7. 没有提交或泄露敏感信息的确认。
```
