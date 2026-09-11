import Foundation

public struct TaskActivity: Decodable, Equatable {
    public let text: String
    public let at: String
}

public struct DashboardTask: Decodable, Identifiable, Equatable {
    public let id: String
    public let project: String
    public var projectID: String? = nil
    public let title: String?
    public let status: String
    public let phase: String
    public let updatedAt: String
    public let startedAt: String
    public let stale: Bool
    public let recent: [TaskActivity]
    enum CodingKeys: String, CodingKey {
        case id, project, title, status, phase, stale, recent
        case projectID = "project_id"
        case updatedAt = "updated_at", startedAt = "started_at"
    }
    public var displayTitle: String {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "未命名任务 · \(id.prefix(6))" : name
    }
    public var groupingID: String { projectID ?? "legacy:" + project }
    public var isRunning: Bool { status == "running" && !stale }
    public var needsAttention: Bool { stale || ["needs_approval", "needs_input", "stalled"].contains(status) }
    public var statusLabel: String {
        if stale { return "状态待确认" }
        switch status {
        case "running": return "运行中"
        case "needs_approval": return "等待确认"
        case "needs_input": return "等待回复"
        case "stalled": return "可能停滞"
        case "finished": return "已结束"
        case "interrupted": return "已中断"
        case "untracked": return "尚未监测"
        default: return "状态未知"
        }
    }
}

public struct TaskDashboardSnapshot: Decodable {
    public let updatedAt: String
    public let tasks: [DashboardTask]
    enum CodingKeys: String, CodingKey { case tasks; case updatedAt = "updated_at" }
    public var runningCount: Int { tasks.filter(\.isRunning).count }
    public var attentionCount: Int { tasks.filter(\.needsAttention).count }

    public func projectGroups(activeOnly: Bool) -> [TaskProjectGroup] {
        var groups: [TaskProjectGroup] = []
        for task in tasks where !activeOnly || task.isRunning || task.needsAttention {
            if let index = groups.firstIndex(where: { $0.id == task.groupingID }) {
                groups[index].tasks.append(task)
            } else {
                groups.append(TaskProjectGroup(id: task.groupingID, name: task.project, tasks: [task]))
            }
        }
        return groups
    }
}

public struct TaskProjectGroup: Identifiable {
    public let id: String
    public let name: String
    public var tasks: [DashboardTask]
}

#if canImport(SwiftUI)
import SwiftUI

/// Live foreground state only. No titles or approval capabilities are persisted.
@MainActor public final class TaskDashboardModel: ObservableObject {
    @Published public private(set) var snapshot: TaskDashboardSnapshot?
    @Published public private(set) var approvalCount: Int?
    @Published public private(set) var approvalMessage = "连接中"
    @Published public private(set) var taskError: String?
    @Published public private(set) var loading = false
    private var connectionKey = ""

    public func refresh(base: String, token: String) async {
        guard !loading else { return }
        if connectionKey != base + token {
            snapshot = nil
            approvalCount = nil
            taskError = nil
            connectionKey = base + token
        }
        loading = true
        defer { loading = false }
        async let taskResult = fetchTasks(base: base, token: token)
        async let approvalResult = fetchApprovals(base: base, token: token)
        await taskResult
        await approvalResult
    }

    private func fetchTasks(base: String, token: String) async {
        do {
            let result = try await ApprovalClient.tasks(base: base, token: token)
            guard !Task.isCancelled else { return }
            snapshot = result
            taskError = nil
        } catch {
            taskError = "任务连接失败，请重试"
        }
    }
    private func fetchApprovals(base: String, token: String) async {
        do {
            let result = try await ApprovalClient.list(base: base, token: token)
            guard !Task.isCancelled else { return }
            approvalCount = result.enabled ? result.requests.filter { $0.canDecide() }.count : nil
            approvalMessage = result.enabled ? "查看并处理" : "尚未启用"
        } catch {
            approvalCount = nil
            approvalMessage = "连接失败"
        }
    }
}

public struct OverviewCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    Text(title).font(.subheadline.weight(.medium))
                }
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            #if os(watchOS)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            #endif
        }
        .foregroundStyle(readableTint)
        .padding(.horizontal, 12).padding(.vertical, cardVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    private var readableTint: Color {
        guard colorScheme == .light else { return tint }
        if tint == .cyan { return .blue }
        if tint == .orange { return Color(red: 0.65, green: 0.30, blue: 0.0) }
        if tint == .green { return Color(red: 0.0, green: 0.44, blue: 0.20) }
        return tint
    }
    private var cardVerticalPadding: CGFloat {
        #if os(watchOS)
        return 4
        #else
        return 11
        #endif
    }
}

public struct TaskOverviewLinks: View {
    @ObservedObject var model: TaskDashboardModel
    let base: String
    let token: String
    private var running: String {
        model.taskError == nil ? model.snapshot.map { String($0.runningCount) } ?? "—" : "—"
    }
    public var body: some View {
        NavigationLink {
            TaskListView(model: model, base: base, token: token)
        } label: {
            OverviewCard(title: "运行中", value: running,
                         subtitle: model.taskError != nil ? "连接失败" : model.snapshot.map { $0.attentionCount > 0 ? "\($0.attentionCount) 项需关注" : "查看任务阶段" } ?? "正在连接 Mac",
                         symbol: "bolt.fill", tint: .cyan)
        }.buttonStyle(.plain)
        NavigationLink {
            ApprovalInboxView(base: base, token: token)
        } label: {
            OverviewCard(title: "待审批", value: model.approvalCount.map(String.init) ?? "—",
                         subtitle: model.approvalMessage, symbol: "checkmark.shield.fill", tint: .orange)
        }.buttonStyle(.plain)
    }
}

public struct TaskListView: View {
    @ObservedObject var model: TaskDashboardModel
    let base: String
    let token: String
    @State private var activeOnly = false
    public var body: some View {
        List {
            Picker("显示", selection: $activeOnly) {
                Text("进行中与待处理").tag(true)
                Text("全部任务").tag(false)
            }
            if let error = model.taskError {
                Text(error + "；以下为上次读取的记录。").font(.caption).foregroundStyle(.orange)
            }
            let groups = model.snapshot?.projectGroups(activeOnly: activeOnly) ?? []
            if groups.isEmpty {
                Label(model.snapshot == nil ? "等待任务数据" : activeOnly ? "当前没有进行中的任务" : "当前没有任务", systemImage: "tray")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.tasks) { task in
                        NavigationLink {
                            TaskProgressView(id: task.id, model: model, base: base, token: token)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(task.displayTitle).font(.headline).lineLimit(2)
                                Text(task.statusLabel).font(.caption.weight(.semibold))
                                    .foregroundStyle(task.needsAttention ? Color.orange : task.isRunning ? Color.cyan : Color.secondary)
                                Text(task.phase).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 4)
                        }
                    }
                } header: {
                    Label("\(group.name) · \(group.tasks.count)", systemImage: "folder")
                        .textCase(nil)
                }
            }
            Button("刷新任务") { Task { await model.refresh(base: base, token: token) } }.disabled(model.loading)
        }
        .navigationTitle("任务")
    }
}

public struct TaskProgressView: View {
    let id: String
    @ObservedObject var model: TaskDashboardModel
    let base: String
    let token: String
    public var body: some View {
        List {
            if let task = model.snapshot?.tasks.first(where: { $0.id == id }) {
                Section {
                    Text(task.displayTitle).font(.headline)
                    Text(task.project).font(.caption).foregroundStyle(.secondary)
                }
                Section("当前阶段") {
                    Text(task.phase).font(.body.weight(.medium))
                    Label(task.statusLabel, systemImage: task.needsAttention ? "exclamationmark.circle" : "circle.fill")
                        .font(.caption).foregroundStyle(task.needsAttention ? Color.orange : Color.cyan)
                    if task.stale || model.taskError != nil {
                        Text("这条状态尚未得到更新，请确认 Mac 是否在线。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text("阶段来自最近活动，不代表完成百分比。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if task.status == "needs_approval" {
                    NavigationLink("查看待审批", destination: ApprovalInboxView(base: base, token: token))
                        .foregroundStyle(.orange)
                }
                Section("最近事件") {
                    if task.recent.isEmpty { Text("等待下一次任务活动").foregroundStyle(.secondary) }
                    ForEach(Array(task.recent.enumerated()), id: \.offset) { _, event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.text).font(.callout)
                            Text(TaskTime.label(event.at)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("最近活动 · " + TaskTime.label(task.updatedAt)).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("任务已更新，请返回任务列表查看。")
            }
        }.navigationTitle("任务详情")
    }
}
#endif

public enum TaskTime {
    public static func label(_ raw: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: raw)
        if date == nil { parser.formatOptions = [.withInternetDateTime]; date = parser.date(from: raw) }
        return date?.formatted(date: .abbreviated, time: .shortened) ?? "时间未知"
    }
}
