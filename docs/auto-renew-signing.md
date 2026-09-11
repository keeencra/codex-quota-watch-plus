# 自动续签：定期延长免费个人签名

免费 Personal Team 的描述文件仍然只有 7 天有效期。这个工具在到期前尝试重新构建并安装，使经常连接 Mac 的个人设备更容易保持可用；它不提供永久签名，也不保证无人值守永不断签。

## 运行条件

- Mac 已安装 Xcode、对应平台 SDK 和 Python 3.10 或更高版本。
- Xcode 已登录 Apple 账户，原工程已成功签名安装到自己的 iPhone 和 Apple Watch。
- Mac 开机联网，安装时设备可连接；设备解锁、信任或账户确认可能需要人工完成。
- 使用 Codex 定时任务时，Mac 和 Codex 需要处于可执行本地任务的状态；不能依赖睡眠或离线期间准点运行。

工具默认在剩余不足 48 小时时构建。它沿用原 Bundle ID、Team 和设备，不卸载应用；手机安装包含小组件，手表单独检查安装结果。

## 1. 建立私有配置

从 [配置示例](examples/renew-signing-config.example.json) 复制一份到本用户的 `~/Library/Application Support/CodexQuotaWatch/renew-signing-config.json`，用自己的值填写所有占位符并将文件权限设为 `600`。不要把填写后的文件提交到 GitHub。

- `project`：自己已签名工程的 `.xcodeproj` 目录绝对路径。
- `derived_data`：续签专用构建目录，建议放在本用户的 Library/Caches 中，与日常开发构建分开。
- `team_id`：原签名 Team。
- `devices`：`xcrun devicectl list devices` 中对应手机和手表的 CoreDevice 标识。
- `apps.*.device_udid`：原描述文件注册的设备 UDID，与上面的 CoreDevice 标识不同。
- `apps.*.bundle_id`：实际已安装应用的标识，包括小组件和 Watch 后缀；不要直接沿用示例值。

三份配置均与实际嵌入式描述文件核对。脚本输出不包含 Team、设备标识或密钥；本机构建日志可能包含这些信息，请勿公开。

## 2. 记录已安装版本的初始到期时间

只有确认手机和手表已成功安装了对应构建产物，才执行以下初始化。这里不能随便选一个旧缓存目录：

```bash
python3 scripts/renew_signing.py --record-installed-from /absolute/path/to/DerivedData/Build/Products
```

它读取三份描述文件、核对应用和设备身份，创建私有 `renew-signing-state.json`。这一步是操作人员对已安装版本的记录，不是远程读取设备签名；已有状态时会拒绝覆盖。

检查当前状态：

```bash
python3 scripts/renew_signing.py --check
```

默认私有状态目录是 `~/Library/Application Support/CodexQuotaWatch`；也可通过 `--state-dir /absolute/path/to/private-state` 使用独立目录，后续每次运行需保持一致。

## 3. 按需续签与设置定时任务

执行：

```bash
python3 scripts/renew_signing.py
```

未到期返回 `not_due`，不构建。进入窗口后通过 Xcode 自动签名构建，并验证描述文件确实延长且还剩超过 48 小时；安装成功才更新对应设备的记录。构建成功但 Apple 返回旧描述文件时返回 `needs_attention`，不会误报续签完成。

如果使用 Codex，可请求它建立一个**本地定时任务**，例如：

> 每天当地时间 10:00 和 20:00，用本机 Python 的绝对路径运行本仓库 scripts/renew_signing.py 的绝对路径。未到期时安静结束；续签成功报告新到期时间；需要人工处理时读取私有日志并简要提醒，同类未变化的问题不要反复打扰。不要将旧缓存或构建成功当作安装续签成功。

**克隆仓库或运行脚本不会自动建立计划任务。** 每个用户需要在自己的 Mac 中单独创建定时任务；本仓库不包含发布者的定时任务、设备配置或凭据，也不使用 GitHub Actions 为个人设备签名。

## 状态和故障处理

- `not_due` / `check_only`：当前无需续签或只做检查。
- `renewed`：本次目标设备安装成功，查看 `installed_expires` 的 UTC 时间。
- `needs_attention`：查看 `RenewalLogs`，它位于 `derived_data` 的父目录中。可能需要连接／解锁设备、重新登录 Xcode，或者等待 Apple 重新签发描述文件后再试。
- `already_running`：另一次续签尚未结束，本次不重复执行。

安装失败不会提前更新记录；手机成功而手表失败时仅推进手机和小组件的到期时间。最终失败返回非零退出码。脚本不删除或吊销签名证书；如果 Apple 没有签发新描述文件，它不会强行绕过签名机制。

## 已验证与限制

有自动测试覆盖到期门槛、小组件到期触发手机安装、旧描述文件不算续签成功、部分安装失败保留旧记录、初始化和配置错误。检查模式已在真实个人签名配置上运行。首次下一周期的真实续签仍需临近到期时实机确认。

参考：[Apple Personal Team 说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。
