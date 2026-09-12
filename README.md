<div align="center">

# 码伴 · CodeCompanion

**项目版本 v3.0.0 · 大更新 · 第 11 次迭代** · [查看各版本变化](CHANGELOG.md#版本索引)

新增产品功能／行为升主版本，仅修产品 Bug 升修订号；日志、介绍与配图等文档修改不升版本。详见[版本规则](CHANGELOG.md#版本号规则)。

### 随身的 AI 开发助手，手机即可使用。

项目与任务 · 远程审批 · 额度与余额 · 小组件与提醒

[所有版本下载](docs/downloads.md) · [界面展示](#界面展示) · [开始部署](#开始部署) · [更新日志](CHANGELOG.md) · [功能文档](#功能文档) · [反馈问题](https://github.com/keeencra/codex-quota-watch-plus/issues)

<img src="docs/assets/brand/codecompanion-master-v3.0.0.png" alt="码伴新图标：绿黄额度环、终端符号和任务确认勾" width="180">

<img src="docs/assets/brand/codecompanion-hero-v3.0.0.svg" alt="码伴：手机独立使用，Apple Watch 可选，Mac 提供数据" width="100%">

*功能示意图，数字为演示数据。*

</div>

**码伴 · CodeCompanion**（原 Codex Quota Watch Plus）是一套面向 iPhone 的 AI 开发助手。**Mac＋iPhone 即可使用，Apple Watch 为可选扩展。** 手机可以查看项目与任务、处理支持的审批请求、监控 Codex 额度、显示可选 DeepSeek 余额、使用桌面小组件及接收任务提醒；搭配手表后可抬腕查看和审批。

Mac 服务仍需在线提供数据；外出使用需配置 HTTPS。独立品牌保留原有开源许可证、版权与上游致谢。

它适合已经使用 Mac 运行 Codex，希望在离开桌面时仍能掌握任务进展的人。项目由 **keeencra** 持续维护，包含原生 SwiftUI App、iPhone 小组件、Python 后端及部署脚本。

**从小红书旧帖来的朋友：你找对项目了。** 本项目原名 **Codex Quota Watch Plus**，现更名为 **码伴 · CodeCompanion**；仓库地址仍为 `keeencra/codex-quota-watch-plus`，旧链接继续有效，v1.0.0 等历史源码仍可下载。

本次 v3.0.0 包含品牌更新、DeepSeek 余额和小组件两套布局。安装只需 Mac＋iPhone，手表可选；[查看新增内容和 Bug 修复](CHANGELOG.md)。

## 界面展示

以下均为 **v3.0.0 本项目原生 SwiftUI 视图**在隔离模拟器中渲染，任务、审批、额度和余额均为虚构数据。截图不会执行命令，不包含个人账户或配对信息。设置区域直接挂载原页面对应区域，小组件按实际尺寸在宿主中展示，均非真机／桌面截图。

Plus／Pro 截图展示不同数据窗口，**不表示所有该套餐账号固定拥有同样限制**；实际界面以 Codex 返回窗口为准。有／无 DeepSeek 在小组件使用两套布局，App 内未配置时保留配置提示。可点击任意图片查看大图。[完整图库与采集说明](docs/gallery.md)

### 手机：任务、审批与账户状态

| Pro 总览 | Plus 总览 | 项目分组与任务标题 |
| --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/iphone-home-pro-ok.jpg" width="230" alt="v3.0.0 Pro 总览，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-home-plus-ok.jpg" width="230" alt="v3.0.0 Plus 总览，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-tasks-pro-ok.jpg" width="230" alt="v3.0.0 项目分组与任务标题，模拟器虚构数据展示"> |

| 任务详情 | 待审批列表 | 逐项确认操作 |
| --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/iphone-task-pro-ok.jpg" width="230" alt="v3.0.0 任务详情，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-approvals-pro-ok.jpg" width="230" alt="v3.0.0 待审批列表，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-approval-pro-ok.jpg" width="230" alt="v3.0.0 逐项确认操作，模拟器虚构数据展示"> |

| Pro 额度 | Plus 额度 | DeepSeek 双币种详情 |
| --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/iphone-quota-pro-ok.jpg" width="230" alt="v3.0.0 Pro 额度，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-quota-plus-ok.jpg" width="230" alt="v3.0.0 Plus 额度，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-balance-pro-ok.jpg" width="230" alt="v3.0.0 DeepSeek 双币种详情，模拟器虚构数据展示"> |

### 小组件：四种组合，各自保留完整布局

每张图从上到下依次为小号、中号、刷新失败时的中号。无 DeepSeek 保留 Codex 原版内容与今日用量图；有 DeepSeek 保留额度进度条，并显示分币种余额。

| Pro · 有 DeepSeek | Pro · 无 DeepSeek |
| --- | --- |
| <img src="docs/assets/gallery/v3.0.0/iphone-widgets-pro-ok.jpg" width="300" alt="v3.0.0 Pro · 有 DeepSeek，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-widgets-pro-not_configured.jpg" width="300" alt="v3.0.0 Pro · 无 DeepSeek，模拟器虚构数据展示"> |

| Plus · 有 DeepSeek | Plus · 无 DeepSeek |
| --- | --- |
| <img src="docs/assets/gallery/v3.0.0/iphone-widgets-plus-ok.jpg" width="300" alt="v3.0.0 Plus · 有 DeepSeek，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-widgets-plus-not_configured.jpg" width="300" alt="v3.0.0 Plus · 无 DeepSeek，模拟器虚构数据展示"> |

### Apple Watch：可选扩展，首页三页与独立功能页

首页通过滑动切换总览、额度和今日用量；进入任务／审批／额度详情后，返回按钮回到上一页，不出现重复分页。

| Pro 总览 | Plus 总览 | 今日用量 |
| --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/watch-home-pro-ok.jpg" width="220" alt="v3.0.0 Pro 总览，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-home-plus-ok.jpg" width="220" alt="v3.0.0 Plus 总览，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-today-pro-ok.jpg" width="220" alt="v3.0.0 今日用量，模拟器虚构数据展示"> |

| Pro 额度 | Plus 额度 | DeepSeek 详情 |
| --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/watch-quota-pro-ok.jpg" width="220" alt="v3.0.0 Pro 额度，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-quota-plus-ok.jpg" width="220" alt="v3.0.0 Plus 额度，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-balance-pro-ok.jpg" width="220" alt="v3.0.0 DeepSeek 详情，模拟器虚构数据展示"> |

| 项目与任务 | 任务详情 | 待审批 | 操作确认 |
| --- | --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/watch-tasks-pro-ok.jpg" width="190" alt="v3.0.0 项目与任务，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-task-pro-ok.jpg" width="190" alt="v3.0.0 任务详情，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-approvals-pro-ok.jpg" width="190" alt="v3.0.0 待审批，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-approval-pro-ok.jpg" width="190" alt="v3.0.0 操作确认，模拟器虚构数据展示"> |

### 配置与项目介绍

| Mac 连接与同步 | Bark 提醒设置 | 连接诊断 | 关于码伴 |
| --- | --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/iphone-settings-pro-ok.jpg" width="220" alt="v3.0.0 Mac 连接与同步，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-notifications-pro-ok.jpg" width="220" alt="v3.0.0 Bark 提醒设置，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-diagnostics-pro-ok.jpg" width="220" alt="v3.0.0 连接诊断，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-about-pro-ok.jpg" width="220" alt="v3.0.0 关于码伴，模拟器虚构数据展示"> |

<details>
<summary>展开：无 DeepSeek、空任务／审批、余额查询失败的全部展示</summary>

| Pro · 未配置 DeepSeek | Plus · 未配置 DeepSeek | 未配置余额提示 | 余额查询失败 |
| --- | --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/iphone-home-pro-not_configured.jpg" width="220" alt="v3.0.0 Pro · 未配置 DeepSeek，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-home-plus-not_configured.jpg" width="220" alt="v3.0.0 Plus · 未配置 DeepSeek，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-balance-pro-not_configured.jpg" width="220" alt="v3.0.0 未配置余额提示，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-balance-pro-error.jpg" width="220" alt="v3.0.0 余额查询失败，模拟器虚构数据展示"> |

| 手机空任务 | 手机无待审批 |
| --- | --- |
| <img src="docs/assets/gallery/v3.0.0/iphone-tasks-empty-pro-ok.jpg" width="230" alt="v3.0.0 手机空任务，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/iphone-approvals-empty-pro-ok.jpg" width="230" alt="v3.0.0 手机无待审批，模拟器虚构数据展示"> |

| 手表空任务 | 手表无待审批 | 手表未配置余额 | 手表余额查询失败 |
| --- | --- | --- | --- |
| <img src="docs/assets/gallery/v3.0.0/watch-tasks-empty-pro-ok.jpg" width="190" alt="v3.0.0 手表空任务，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-approvals-empty-pro-ok.jpg" width="190" alt="v3.0.0 手表无待审批，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-balance-pro-not_configured.jpg" width="190" alt="v3.0.0 手表未配置余额，模拟器虚构数据展示"> | <img src="docs/assets/gallery/v3.0.0/watch-balance-pro-error.jpg" width="190" alt="v3.0.0 手表余额查询失败，模拟器虚构数据展示"> |

</details>

## 一天中可以怎样使用

1. **在 Mac 开始任务**：照常使用 Codex。已配置的 Hooks 与观察器采集活动，不需要在手表重新创建任务。
2. **离开桌面时看进展**：手机或手表打开「运行中」，查看任务标题、当前阶段及最近事件；「正在执行工具」表示实际活动阶段，不是估算百分比。
3. **遇到需要确认的操作**：收到提醒后，打开橙色「待审批」，核对完整操作，再批准本次或拒绝。只有已接入且仍在等待的请求可以处理。
4. **结束后收到静音提醒**：Bark 可镜像到 Apple Watch；已结束的任务仍能在「全部任务」里查看。可开启「项目名 · 任务标题 · 本轮已结束」，多任务并行时能区分来源；不读取或发送消息正文。
5. **随时检查剩余额度**：绿色入口、小组件和手表额度页显示实际窗口及更新时间。外出访问需要提前配置 HTTPS，并让 Mac 保持运行。

## DeepSeek 账户余额

手机与手表总览新增 DeepSeek 入口，可查看人民币／美元总余额、充值余额、赠送余额和采集时间；手机小号／中号桌面小组件也显示双币种余额。API Key 仅保留在 Mac，沿用原 HTTPS 配对同步。[配置与使用](docs/deepseek-balance.md)。

## 功能一览

| 能力 | iPhone | Apple Watch | Mac 端负责什么 |
| --- | --- | --- | --- |
| 任务总览 | 运行中、需关注与待审批数量 | 同样的三项总览 | 汇总已跟踪会话的最新状态 |
| 任务进展 | 项目分组、侧栏标题、筛选、阶段与事件 | 项目分组及任务详情 | Hooks + 增量日志观察，处理旧状态 |
| 逐项审批 | 查看完整操作、批准或拒绝 | 查看完整操作、批准或拒绝 | 接收支持的请求、检验有效期并返回决定 |
| 额度监控 | 套餐、窗口、重置、今日 Tokens | 额度页与今日用量页 | 读取本机 Codex 返回的额度与用量 |
| 手机桌面小组件 | 小号／中号，独立刷新与缓存提示 | 本项目未提供表盘复杂功能 | 通过认证接口提供额度数据 |
| 任务提醒 | Bark 静音通知，兼容 ntfy | 镜像 iPhone 通知 | 去重、重试、过期和停滞检查 |
| 外出访问 | 通过固定 HTTPS 地址连接 | 通过配置的互联网连接访问 | 运行认证网关与隧道，Mac 必须在线 |
| 自动续签 | 满足条件时重新安装签名包 | 随配套流程续签安装 | 检查签名、构建、安装并记录结果 |

## 打开手表，先看三件事

| 首页卡片 | 你能看到什么 | 点进去可以做什么 |
| --- | --- | --- |
| 🔵 **运行中** | 已跟踪的运行任务数量，另列需要关注的任务 | 查看任务标题、当前阶段、状态和最近事件 |
| 🟠 **待审批** | 仍在等待你决定的实时审批数量 | 查看完整操作，批准本次或拒绝本次 |
| 🟢 **剩余额度** | Codex 实际返回的剩余额度 | 查看各额度窗口、重置时间和套餐信息 |

任务阶段来自实际活动，例如“正在分析”“正在执行工具”“正在整理回复”，不会猜测完成百分比。过旧状态会标记待确认；连接失败时显示未知数量，避免把旧数据当成实时状态。

手机首页使用相同的三项总览。配对、通知与诊断设置可展开查看；手表左右滑动仍可进入完整额度和今日用量页面。

## 从查看状态，到处理关键节点

**任务进展与提醒。** 结束提醒可显示「产品开发 · 修复小组件 · 本轮已结束」，名称随 Codex 侧栏同步。Hooks 与增量日志观察器共同记录运行、等待回复、结束和中断等状态，并去重。活动任务约 10 分钟没有新事件时，可发送“可能停滞”提醒。Bark 默认为静音通知，保留 ntfy 兼容；Apple Watch 可镜像手机通知。

**手表远程审批。** 支持已接入的桌面原生命令审批和 `PermissionRequest` Hook。每次展示具体操作，再由你确认；请求过期、失去等待进程或任务结束后失效。不会自动批准，也不会把批准扩展为永久授权。原生文件变更审批和文字问答等仍需在 Mac 处理，详见 [审批支持范围](docs/remote-approval.md)。

**额度与小组件。** 显示 Plus / Pro 等套餐标签、可用额度窗口、重置时间，以及今日输入、输出和缓存 token。只展示数据源实际返回的窗口。iPhone 小号、中号小组件可独立刷新额度；系统决定后台刷新时机，网络失败时保留缓存并提示未更新。

**外出访问。** 使用认证 HTTPS 网关与 ngrok 固定地址，手机／手表通过互联网访问 Mac，无需一直处于同一局域网。Mac 仍需开机、联网并运行服务；隧道不能代替 Mac 执行任务。

**自动续签。** 提供签名检查、重新构建及安装工具。在满足设备连接、账号和签名条件时，可配合定时任务在临近过期前尝试续签，并核对有效期与安装结果。免费签名不是永久签名，续签失败仍需处理，详见 [自动续签配置](docs/auto-renew-signing.md)。

## 数据如何到达手腕

```mermaid
flowchart LR
    Codex[Mac 上的 Codex] --> Agent[本机任务与额度服务]
    Agent --> Gateway[认证 HTTPS 网关]
    Gateway --> Phone[iPhone 总览与小组件]
    Gateway --> Watch[Apple Watch 总览]
    Phone -->|额度同步| Watch
    Agent --> Bark[Bark 静音提醒]
    Bark --> Phone
    Watch -->|你确认的本次决定| Gateway
    Gateway -->|返回仍在等待的请求| Codex
```

任务与审批在 App 前台每 10 秒读取。额度刷新和系统小组件有各自的周期，详细说明见 [任务总览](docs/task-dashboard.md) 与 [远程访问设置](docs/enhancements.md)。

## 开始部署

下载历史版本或当前版本，请进入 [所有版本下载](docs/downloads.md)；每个版本都有固定源码 ZIP 入口。

需要一台运行 Codex 的 Mac、Xcode 和 iPhone；Apple Watch 可选，没有手表也可完成手机配置。原生 App 需要自行构建和签名，本仓库不提供 App Store 安装包。

### 1. 下载并启动基础额度服务

```bash
git clone https://github.com/keeencra/codex-quota-watch-plus.git
cd codex-quota-watch-plus
scripts/install-launch-agent.sh --lan
```

### 2. 安装手机、手表和小组件

```bash
scripts/configure-ios-identifiers.sh --bundle-id com.yourname.CodexQuota
open ios-watch/CodingQuota.xcodeproj
```

为 `CodingQuota`、`CodingQuota Watch App`、`CodingQuotaWidgetExtension` 三个 target 选择自己的 Apple Team，并按 [完整安装文档](docs/setup.md) 完成设备信任、开发者模式与真机安装。

```bash
scripts/show-pairing-qr.sh --open-html
```

iPhone App → **连接与同步 → Mac 连接设置 → 扫描配对二维码**，配对后点 **同步额度到手表**。二维码包含访问凭据，请保留在自己的设备上。

### 3. 开启完整功能

| 功能 | 配置入口 |
| --- | --- |
| HTTPS 外网访问、Bark 静音提醒、任务事件采集 | [远程访问与任务提醒](docs/enhancements.md) |
| 手表任务标题、阶段与总览 | [任务总览及数据说明](docs/task-dashboard.md) |
| 逐项远程批准／拒绝 | [远程审批配置](docs/remote-approval.md) |
| 临近过期时尝试重新签名 | [自动续签工具](docs/auto-renew-signing.md) |

基础配对只完成额度同步。任务总览与远程审批还需部署 HTTPS 网关、任务事件服务，并显式启用审批功能。更新后端源码后，请重新安装 Python 包并重启对应服务。

<details>
<summary>让本机 Codex 协助部署</summary>

```text
请按 keeencra/codex-quota-watch-plus 的 README 部署码伴到我的 Mac 和 iPhone；仅在我有 Apple Watch 时额外安装手表端。
先完成基础额度同步，再配置任务总览、HTTPS 远程访问和 Bark 静音提醒。
远程审批按 docs/remote-approval.md 的支持范围逐项配置，不启用自动批准。
保留现有 Codex Hooks，不输出配对 Token、Bark 密钥或签名凭据。
如果必须由我完成 Apple 账号登录、设备信任或开发者模式，请告诉我具体操作。
```

更详细的步骤见 [本机部署提示词](docs/codex-deploy-prompt.md)。

</details>

## 隐私与实际边界

- 默认通知只发送状态；开启任务标识后，结束提醒将项目名和侧栏任务标题发送到已配置的 Bark／ntfy。名称来自本地任务目录，不读取消息正文、命令参数或助手回复；标题本身的内容也会出现在通知中。
- 任务标题经认证接口送到自己的 App，不进入额度缓存或小组件；推送中显示标题需按 [任务提醒配置](docs/enhancements.md#按项目与任务区分结束提醒) 单独开启。
- 审批详情具有操作敏感性。不要共享配对二维码或 `WATCH_TOKEN`；更换凭据见 [安全说明](SECURITY.md)。
- 任务统计限于服务已跟踪的事件，首次安装不会补发历史通知；状态与阶段不是整个项目完成的证明。
- 桌面审批适配器依赖 Codex 本机接口，Codex 升级后需要复验；不支持的请求仍在 Mac 处理。
- 本项目是社区工具，非 OpenAI 或 Apple 官方产品。

## 功能文档

[更新日志](CHANGELOG.md) · [完整安装](docs/setup.md) · [任务总览](docs/task-dashboard.md) · [远程审批](docs/remote-approval.md) · [外网与提醒](docs/enhancements.md) · [自动续签](docs/auto-renew-signing.md) · [常见问题](docs/troubleshooting.md)

开发检查：

```bash
(cd agent && python3 -m pytest)
swift test --package-path ios-watch
scripts/check-public-ready.sh --worktree
```

## 开源与致谢

以 **AGPL-3.0** 发布，详见 [LICENSE](LICENSE)。本项目在 [cyq1017/codex-quota-watch](https://github.com/cyq1017/codex-quota-watch) 基础上持续开发，任务提醒参考 [H1234L1/codex-watch-notifier](https://github.com/H1234L1/codex-watch-notifier)。上游著作权、许可证及其他设计参考见 [来源说明](THIRD_PARTY_NOTICES.md)。
