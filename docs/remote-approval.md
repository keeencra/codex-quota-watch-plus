# 手表远程审批与提醒补充检查

## 使用

iPhone 或 Watch App 打开后，点总览首页的橙色「待审批」卡片。收到 Bark 提醒后打开这一页，查看项目、工具、工作目录和完整参数，再选择「批准本次」或「拒绝本次」。批准需要再次确认。

支持正在等待决定的 `PermissionRequest` Hook，以及桌面 App 的原生命令审批。桌面适配器通过本机用户专属 Unix socket 接入现有 follower 审批路由，不点击界面，不修改权限。默认等待 180 秒；超时、断线、任务中断或等待进程退出后，远程请求失效，请在 Mac 处理。没有全局允许、会话永久允许或离线批准队列。

「已提交」表示网关收到决定；「批准／拒绝已交回 Codex」表示 Hook 已消费决定，或桌面原任务所有者已接受回传，不等于命令已成功执行。其他 Hook 的拒绝、组织规则和执行错误仍可能阻止操作。

Bark 通知本身不能直接批准。`request_user_input` 问答、MCP 引导式表单，以及未触发该 Hook 的审批仍需在 Codex 处理。日志观察器只负责提醒，不能从历史记录创建可批准的请求。

## 本机配置

桌面原生适配器当前仅支持命令审批；文件变更和其他原生审批请在 Mac 处理。适配器校验 stream v11 / command-decision v1 协议、当前任务所有者、请求 ID 和完整参数。版本不匹配、请求已移除或状态补丁缺失时停止远程批准。该本机接口不是稳定公开 API，Codex 更新后需重新验证。

先部署认证 HTTPS 网关和新版手机／手表 App，沿用配对的 `WATCH_TOKEN`。该 Token 现在也能查看敏感审批详情和提交决定，应像操作凭据一样保护；不要共享二维码或 Token。审批请求不进入额度快照、小组件或 Bark。

在私有状态目录 `~/Library/Application Support/CodexQuotaWatch/remote-approval.json` 保存以下内容，文件权限设为 `600`：

```json
{"enabled": true}
```

文件默认不存在，克隆仓库不会启用远程审批。设为 `false` 后，等待中的 Hook 会放弃远程审批并回到本机流程。

把现有 `PermissionRequest` Hook 更新为下面形式，其他任务记录 Hook 仍使用 2 秒。替换 Python 的实际绝对路径，合并配置，保留其他工具的 Hook：

```json
{
  "hooks": {
    "PermissionRequest": [{
      "hooks": [{
        "type": "command",
        "command": "'/absolute/path/to/python' -m codex_watch_agent.task_hook",
        "timeout": 190,
        "statusMessage": "等待手机或手表确认（最多 3 分钟）"
      }]
    }]
  }
}
```

正常完成 Codex Hook 信任审查并重新启动需要使用新配置的会话，不修改信任数据库、不绕过审批规则。

网关新增认证的 `GET /approvals`、`GET /approvals/{id}` 和 `POST /approvals/{id}/decision`。客户端只接受 HTTPS，拒绝重定向，使用内存中的一次性 nonce 和操作指纹提交决定。提交与消费用数据库事务串行处理，重复提交不会重复执行。Hook 每半秒维持活动状态；超过 8 秒未更新或超过 180 秒的请求不可再批准。

完整操作参数只暂存在权限为 `600` 的独立 `approvals.sqlite3`；已消费、取消或过期后清空详情。服务不执行客户端传来的命令，只允许回复已经在等待的具体请求。

## 漏报与停滞检查

通知进程每 10 秒增量读取本机 Codex rollout 日志（`sessions` 与 `archived_sessions`），补充任务结束、中断、等待回复等事件，与 Hooks 共用去重队列。首次启动从现有文件末尾开始，避免重放旧通知。文件游标保存在本机，原始对话和工具输出不保存到任务记录、不发送到推送服务。

仅未归档且日志已追赶到末尾的活动任务，约 10 分钟没有新事件时发送一次「可能停滞」静音提醒。有新活动后恢复计时；等待回复、等待审批、已完成或中断的任务不按运行中停滞处理。它只是活动超时判断，不能证明任务已经卡死。

日志格式是兼容性依赖；格式变动或日志不可用时，Hooks 仍负责正常任务提醒。观察器为独立实现，功能设计参考 [DrXin-code/codex-notify](https://github.com/DrXin-code/codex-notify)，没有复制其源码。

官方接口依据：[PermissionRequest Hook](https://learn.chatgpt.com/zh-Hans/docs/hooks#permissionrequest)。

如需在提醒标题中显示项目目录名，在私有状态目录的 `notification-preferences.json` 写入 `{"include_project":true}`。默认不发送项目名；开启后仍不发送完整路径、操作详情或回复，声音仍为静音。

结束提醒若需同时显示 Codex 项目名与任务标题，可启用 [`include_task_identity`](enhancements.md#按项目与任务区分结束提醒)；此选项不改变审批提醒或审批权限。
