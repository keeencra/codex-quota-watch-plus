# 码伴 Mac

码伴的可选 macOS 显示端，整合 Codex Usage Bar 的菜单栏和 WidgetKit 桌面／通知中心小组件。统一使用码伴品牌与根目录版本规则；原工程历史和 MIT 声明见 [来源说明](UPSTREAM.md)。

## 功能

- 菜单栏圆环与紧凑额度文字，点击打开统一深色滚动面板，连续浏览余额、趋势、每日精确用量、账户与任务详情。
- 按 Codex 实际返回窗口显示 Plus／Pro 等套餐、剩余百分比和重置时间。
- DeepSeek API 余额按币种分别显示，查询余额不调用付费生成模型。
- 大号组件上半区并排显示 Codex 额度与重置卡，下半区显示 DeepSeek CNY／USD 余额。
- 小、中、大号原生小组件；显示额度、余额及接口提供的重置券数量、到期记录。只读展示，不消耗重置券。
- 最近 7 天每日 token 用独立竖向柱状图展示 Codex 与 DeepSeek，包含每日数值和 7 天合计，向下滚动查看精确整数明细；原有本机任务详情保留。
- Codex 按本机会话记录的输入（含缓存）与输出增量统计；DeepSeek 读取本机工具 `~/.codex/tools/deepseek/state/usage.sqlite3`，不含其他软件、其他设备或账户全量用量。今天尚未结束；0 为无已记录用量，— 为记录不可用。
- 手动刷新、关于码伴及手机连接文档入口。

## 构建与安装

在仓库根目录运行 `bash scripts/install-macos.sh`。只构建：`bash macos/build_app.sh`。完整检查：`bash macos/scripts/check.sh`。签名产物默认在 `~/Library/Caches/CodeCompanionMac/build/CodeCompanionMac.app`，避免云同步目录附加属性影响签名；可用 `OUTPUT_DIR` 指定输出位置。

需要完整 Xcode；菜单栏支持 macOS 13 起，小组件需要 macOS 14 起。可用小组件的数据共享需要有效 Apple 开发签名，未签名构建只用于编译验证。未提供公证或 App Store 分发。

安装会沿用旧 Codex Usage Bar 的 bundle ID、URL scheme、App Group 与已安装路径（如果存在），保留小组件配置和共享数据。首次安装使用 `~/Applications/CodeCompanionMac.app`。安装脚本备份被替换的应用及启动配置，只注册一个菜单栏自启动服务。退出桌面程序不停止手机／手表的 Mac 服务。

在桌面选择「编辑小组件」，搜索「码伴」，按需选择「额度速览」或「账户总览」。已有组件可继续读取同一共享容器；macOS 图库更新有延迟，必要时重新打开编辑器。

## 与手机、手表的关系

Mac 显示端可独立运行，不要求先部署 HTTPS 或手机服务。菜单栏和 macOS 小组件共享同一份本地摘要；iPhone／Apple Watch 沿用现有码伴 Python 服务。当前整合统一代码、品牌、部署入口和 DeepSeek 凭据，不强行替换既有手机服务的数据采集。各端独立刷新，数值采样时间可能不同。

DeepSeek 密钥查找顺序：环境变量 `DEEPSEEK_API_KEY` → 码伴本地 `~/Library/Application Support/CodexQuotaWatch/deepseek-api-key` → 旧工具的 `~/.codex/secrets/deepseek-api-key`。不复制密钥，不写入小组件摘要。没有配置时显示状态提示；通过根目录 `scripts/configure-deepseek.py` 配置。

默认约每 60 秒更新本地摘要，小组件重绘由系统调度；五分钟未同步标记待更新。刷新失败显示错误／缓存状态。沿用原工具的本机 Codex 读取方式，不是远程执行或审批客户端；手机连接和审批仍按根目录文档配置。

## 验证边界

来源模块依赖 Codex 本机非稳定 app-server 和 state_5.sqlite。账号切换后的缓存隔离及后台生命周期仍是已知待办，不能把本次合并描述为已经修复这些问题。编译、离屏图片或安装成功不等于所有尺寸、桌面交互都已实机验收。

两端组件分类和添加方法见 [小组件指南](../docs/widgets.md)。经典视图由根目录 `shared-widgets/` 共用，构建需要完整仓库。
