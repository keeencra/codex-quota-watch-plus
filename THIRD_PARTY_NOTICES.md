# 来源与许可证

本仓库基于 [cyq1017/codex-quota-watch](https://github.com/cyq1017/codex-quota-watch)，基线提交 `aeabdac`。保留原项目 AGPL-3.0 许可证，详见 [LICENSE](LICENSE)。本版加入套餐识别、远程网关、小组件刷新及任务通知改动；发布时已移除个人部署配置。

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
