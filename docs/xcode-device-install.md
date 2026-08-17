# Xcode 真机安装演示

目标：把 `Codex Quota` 安装到自己的 iPhone 和 Apple Watch。这里的步骤只处理 Xcode、签名、设备和配对；Mac Agent 安装见 `docs/setup.md`。

## 名字对应关系

Xcode 里看到的名字和设备上看到的名字不同，这是正常的：

| 位置 | 名字 |
|---|---|
| Xcode project | `CodingQuota` |
| iPhone target | `CodingQuota` |
| Watch target | `CodingQuota Watch App` |
| Widget target | `CodingQuotaWidgetExtension` |
| iPhone 主屏 App 名 | `Codex Quota` |
| Apple Watch App 名 | `Codex Quota` |
| iPhone Widget 名 | `Codex Quota` |

如果 Xcode target 叫 `CodingQuota`，但手机上显示 `Codex Quota`，不是注册失败。

## Codex 可以帮你做什么

这个项目适合让本机 Codex 陪你安装，但 Codex 不能替你完成所有 Apple 安全确认。

Codex 可以做：

- 安装和检查 Mac Agent。
- 生成 `WATCH_TOKEN` 和配对二维码，但不打印真实 token。
- 运行 `scripts/configure-ios-identifiers.sh` 配置 Bundle ID。
- 检查 Xcode SDK、runtime、设备列表和 build 错误。
- 打开 Xcode 项目，并告诉你下一步点哪里。
- 在 Xcode 配置完成后继续运行验证命令。

你必须自己做：

- 在 `Xcode > Settings... > Accounts` 登录或刷新 Apple ID。
- 在三个 target 的 `Signing & Capabilities` 里选择同一个 Team。
- 在 iPhone 上信任这台 Mac、开启 Developer Mode、信任开发者证书。
- 在 Xcode 要求时允许修复 signing/provisioning。
- 扫码配对，不要把二维码或 `WATCH_TOKEN` 截图公开。

可以把 `docs/codex-deploy-prompt.md` 里的 prompt 复制给 Codex，让它按这个边界带你走完整流程。

## 1. 安装 Xcode 平台组件

打开 Xcode 后先检查平台组件：

1. 打开 `Xcode > Settings... > Components`。
2. 确认安装了你的 iPhone iOS 版本对应的 iOS platform。
3. 确认安装了你的 Apple Watch watchOS 版本对应的 watchOS platform。

如果命令行或 Xcode 报：

```text
watchOS 26.5 is not installed. Please download and install the platform from Xcode > Settings > Components.
```

先安装对应 watchOS platform，再继续。这个错误发生在签名前，和 Bundle ID、Apple Team 还没有关系。

这个下载可能接近 4GB，第一次安装会比较慢。高级用户也可以用命令行安装：

```bash
xcodebuild -downloadPlatform watchOS
```

如果 `xcodebuild -showsdks` 能看到 watchOS SDK，但 Run 仍然报缺 watchOS platform，还是回到
`Xcode > Settings... > Components` 安装对应 watchOS runtime/platform。

检查命令：

```bash
xcodebuild -showsdks
xcrun simctl list runtimes
xcodebuild -project ios-watch/CodingQuota.xcodeproj -scheme CodingQuota -showdestinations
```

如果 `xcrun simctl list runtimes` 没有对应 watchOS runtime，说明 Xcode Components 还没装完整。

## 2. 配置自己的 Bundle ID

在仓库根目录运行：

```bash
scripts/configure-ios-identifiers.sh --bundle-id com.yourname.CodexQuota
```

把 `com.yourname.CodexQuota` 换成你自己的反向域名格式。脚本会同步：

- iPhone App Bundle ID
- Watch App Bundle ID
- App Group entitlement
- Watch companion iPhone Bundle ID
- 后台刷新 task id

不要把 Apple Team ID、证书、描述文件或真实账号信息写进仓库。

## 3. 打开项目

```bash
open ios-watch/CodingQuota.xcodeproj
```

Xcode 左侧最上层应看到 project `CodingQuota`。如果只看到一堆文件，没有 target 设置面板，点左侧导航最上面的蓝色 project 图标。

## 4. 给三个 target 选同一个 Team

先确认 Xcode 已登录 Apple ID：

1. 打开 `Xcode > Settings... > Accounts`。
2. 添加或选中你的 Apple ID。
3. 确认账号状态不是过期、未登录或需要重新认证。

在 Xcode 中依次选择这三个 target：

```text
CodingQuota
CodingQuota Watch App
CodingQuotaWidgetExtension
```

每个 target 都做一次：

1. 打开 `Signing & Capabilities`。
2. 勾选或保持 `Automatically manage signing`。
3. `Team` 选择同一个 Apple Team。
4. 确认 `Bundle Identifier` 已经是你刚才配置的值，不再是 `com.example...`。
5. 确认 `App Groups` 是同一个 group，例如 `group.com.yourname.CodexQuota`。

如果 Xcode 在 App Groups 这里报 signing/provisioning 错误，先不要继续 Run。优先让 Xcode 修复 signing；如果你的账号暂时无法使用 App Groups，可以临时从三个 target 的
`Signing & Capabilities` 里移除 App Groups 后再测基础安装和 WatchConnectivity 同步。这个临时改动只用于本机验证，不建议提交到仓库。

## 5. 选择设备并运行

1. 用数据线或无线调试连接 iPhone。
2. 确认 iPhone 和 Apple Watch 已配对。
3. Xcode 顶部 scheme 选择 `CodingQuota`。
4. 运行设备选择你的 iPhone，不要选 `My Mac`。
5. 点 Run。

第一次真机运行可能会要求：

- iPhone 开启 Developer Mode。
- iPhone 信任这台 Mac。
- iPhone 在 `Settings > General > VPN & Device Management` 里信任开发者证书。
- Xcode 修复 signing/provisioning。

这些都是 Apple 真机调试流程，不是本项目自己的登录或注册步骤。

确认自己没有选错目标：

| 正确 | 不要选 |
|---|---|
| scheme: `CodingQuota` | scheme: `CodingQuota Watch App` 作为首次安装入口 |
| destination: 你的实体 iPhone | destination: `My Mac`、模拟器或某个 Watch simulator |
| Run companion iPhone app | 只 Run Watch target |

第一次安装建议总是从 iPhone companion app 跑起。Xcode 会把 embedded Watch App 一起打包；如果 watchOS 没有自动下发，再用本页下面的 `devicectl install app` 手动补装 Watch app。

如果命令行或 Xcode 报：

```text
No Account for Team "<Team ID>"
No profiles for '<bundle-id>' were found
```

说明 Xcode 还没有登录这个 Team，或账号凭证过期。先回到 `Xcode > Settings... > Accounts` 修复账号，再重新 Run。

如果让 Codex 帮你跑命令行真机 build，应该使用仓库外的 DerivedData 路径，例如：

```bash
xcodebuild \
  -project ios-watch/CodingQuota.xcodeproj \
  -scheme CodingQuota \
  -configuration Debug \
  -destination 'id=<你的 iPhone device id>' \
  -derivedDataPath /tmp/coding-quota-derived-data \
  build
```

不要把 `DerivedData`、Team ID、provisioning profile、签名证书或 Xcode 用户配置提交到仓库。

## 6. 确认安装结果

安装成功后：

1. iPhone 主屏应出现 `Codex Quota`。
2. Apple Watch 上应出现 `Codex Quota`；如果没有，打开 iPhone 上的 Watch App，在已安装应用列表里确认。
3. 如果 Watch App 没有立刻出现，等一会儿，或在 Xcode 再运行一次 iPhone target。

如果 iPhone 上已经有 `Codex Quota`，但 Apple Watch 上始终没有，可以把 embedded Watch App 直接安装到手表。先找 Watch 的 device id：

```bash
xcrun devicectl list devices
```

如果你前面用了 `/tmp/coding-quota-derived-data` 命令行 build，直接安装：

```bash
xcrun devicectl device install app \
  --device <你的 Apple Watch device id> \
  "/tmp/coding-quota-derived-data/Build/Products/Debug-iphoneos/CodingQuota.app/Watch/CodingQuota Watch App.app"
```

如果你是直接在 Xcode 里点 Run，产物通常在 `~/Library/Developer/Xcode/DerivedData`。可以这样找最新的 embedded Watch App：

```bash
find ~/Library/Developer/Xcode/DerivedData \
  -path '*CodingQuota.app/Watch/CodingQuota Watch App.app' \
  -type d -print |
while IFS= read -r path; do
  stat -f '%m %N' "$path"
done |
sort -nr |
head -1
```

复制输出里时间戳后面的完整路径，再安装到 Watch：

```bash
xcrun devicectl device install app \
  --device <你的 Apple Watch device id> \
  "<上一步找到的完整 Watch App.app 路径>"
```

再确认：

```bash
xcrun devicectl device info apps --device <你的 Apple Watch device id> | grep "Codex Quota"
```

如果命令提示手表锁定，先解锁 Apple Watch，再从手表 app 列表打开 `Codex Quota`。

`devicectl` 偶尔会报 tunnel timeout，例如：

```text
Timed out while attempting to establish tunnel using negotiated network parameters
```

这通常是 Xcode/CoreDevice 到手表的连接瞬断，不代表 app 包坏了。保持 Apple Watch 亮屏解锁、靠近 iPhone，确认 Mac/iPhone/Watch 在可达网络上，然后重试同一条安装命令。

## 7. 扫码配对

Mac 上运行：

```bash
scripts/show-pairing-qr.sh --open-html
```

如果当前环境不能自动打开浏览器，再用终端二维码备用：

```bash
scripts/show-pairing-qr.sh
```

iPhone 上打开 `Codex Quota`：

1. 点 `Scan Pairing QR`。
2. 扫浏览器页面里的二维码。
3. 点 `Fetch & Sync to Watch`。
4. 打开 Apple Watch 上的 `Codex Quota`。

二维码包含 `WATCH_TOKEN`，不要截图公开，不要发给别人。如果浏览器二维码页已经用完，可以直接关闭。

## 常见卡点

### Xcode 看不到 Watch 设备

先确认 Apple Watch 已和当前 iPhone 配对，并且 Xcode 已安装对应 watchOS platform。缺 platform 时，Xcode 会把 Watch 标成 ineligible。

### 能装 iPhone，Watch 没出现

先等几分钟，然后打开 iPhone 的 Watch App 查看 `Codex Quota` 是否已安装。仍没有时，在 Xcode 里重新 Run `CodingQuota` scheme 到 iPhone。

如果 iPhone 已安装但 Watch 仍没有，说明 companion 没有自动下发到手表。按上面的 `xcrun devicectl device install app --device <你的 Apple Watch device id> ...Watch App.app` 手动安装一次。

### Bundle ID 报重复

换一个更唯一的 Bundle ID，例如：

```text
com.yourname.CodexQuota.Dev
```

然后重新运行：

```bash
scripts/configure-ios-identifiers.sh --bundle-id com.yourname.CodexQuota.Dev
```

### App Group 报错

确保三个 target 使用同一个 Team，并且 App Group 名一致。如果 Xcode 仍然无法生成 provisioning profile，先修复 signing；临时本机验证时可以移除 App Groups capability 再测基础安装和 WatchConnectivity 同步，但不要把这个临时改动提交。

### 安装后找不到 App

设备上显示名是 `Codex Quota`，不是 `CodingQuota`。
