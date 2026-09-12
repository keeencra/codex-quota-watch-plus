# v3.0.0 图库采集说明

本图库直接复用发布源码的 SwiftUI 视图，使用隔离模拟器宿主，不是根据设计稿绘制的假界面。示例任务、审批与余额完全虚构；网络请求替换为固定响应，审批提交被拒绝，不连接真实服务或执行命令。

- 手机：总览、项目任务列表／详情、额度、审批列表／详情、DeepSeek、Mac 设置、通知、诊断、关于页面。
- 手表：总览、额度、今日用量、项目任务、审批及 DeepSeek。
- 变体：Plus／Pro；DeepSeek 已配置／未配置；空任务／无待审批；余额错误；小号、中号及刷新失败小组件。
- 设置截图在宿主内直接挂载原页面对应区域，默认展开折叠项，以便完整展示。小组件为 160×160／344×160 固定尺寸宿主，非桌面截图。滚动页面截图为首屏，不承诺覆盖每一个系统弹窗。
- `fixtures.json` 保存虚构数据，`manifest.json` 列出每张截图的状态；任务期限按采集时刻生成。每个币种独立显示，套餐窗口仅为演示组合，以真实 API 返回为准。

从仓库根目录执行，设备 ID 使用自己的模拟器 ID（不是真机）：

```bash
python3 docs/gallery/prepare.py
xcodebuild -project /tmp/codecompanion-v3-gallery/ios-watch/CodingQuota.xcodeproj \
  -scheme 'CodingQuota Watch App' -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath /tmp/CodeCompanionV3GalleryBuild CODE_SIGNING_ALLOWED=NO build
python3 docs/gallery/capture.py --iphone '<iPhone 模拟器 ID>' --watch '<Watch 模拟器 ID>'
```

采集会更新隔离模拟器中的示例 App；不安装到真机、不更改正式源码或私有配置。Xcode／模拟器系统版本、字体和时间会影响输出，当前图片采集于 iOS／watchOS 26.5 模拟器。
