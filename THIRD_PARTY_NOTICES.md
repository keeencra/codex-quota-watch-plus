# 来源与许可证

本仓库基于 [cyq1017/codex-quota-watch](https://github.com/cyq1017/codex-quota-watch)，基线提交 `aeabdac`。保留原项目 AGPL-3.0 许可证，详见 [LICENSE](LICENSE)。本版加入套餐识别、远程网关、小组件刷新及任务通知改动；发布时已移除个人部署配置。

上游 README 著作权署名：AGPL-3.0 © 2026 从野秦。keeencra 维护的改进版另加入任务总览、原生远程审批、活动观察器、静音提醒与自动续签等功能；仓库首页及新的功能示意图为本版重新编写和绘制。

活动补充检查的功能设计参考 [DrXin-code/codex-notify](https://github.com/DrXin-code/codex-notify)；任务／审批／额度的信息层级参考用户提供的 [腕令展示帖](https://www.xiaohongshu.com/explore/6aa0becd000000002802e77f)。这两项参考未向本仓库引入对方源代码、图片或品牌素材。

任务通知方案参考 [H1234L1/codex-watch-notifier](https://github.com/H1234L1/codex-watch-notifier)，其 MIT 声明保留如下。Bark 通过公开 HTTP API 使用，[Bark](https://github.com/Finb/Bark) / [bark-server](https://github.com/Finb/bark-server) 源码未打包到本仓库。

# Task notification integration

The task event / ntfy integration was inspired by [H1234L1/codex-watch-notifier](https://github.com/H1234L1/codex-watch-notifier). The adapted implementation uses local SQLite history and a status-only notification outbox instead of forwarding prompts or commands. The upstream license is reproduced below.

MIT License

Copyright (c) 2026 codex-watch-notifier contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## Codex Usage Bar / 码伴 Mac 模块

`macos/` 整合所有者维护的 Codex Usage Bar 现有实现，原 MIT 版权与许可保留在 [macos/LICENSE](macos/LICENSE)，来源和整合范围见 [macos/UPSTREAM.md](macos/UPSTREAM.md)。码伴根目录 AGPL-3.0 及已有上游版权保持不变。
