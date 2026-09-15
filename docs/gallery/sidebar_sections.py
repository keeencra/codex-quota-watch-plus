"""Prepare an isolated simulator host using real task views and fictional data."""
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[2]
destination = Path('/tmp/codecompanion-sidebar-gallery')
for folder in ['ios-watch', 'shared-widgets', 'macos']:
    shutil.copytree(root / folder, destination / folder, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('.build', 'build', 'xcuserdata', '.git'))
stamp = '2026-09-15T02:00:00Z'
tasks = [dict(id='demo-'+str(i), project=name, project_id=str(i), title=title,
              status='finished', phase='本轮处理已结束', updated_at=stamp,
              started_at=stamp, stale=False, recent=[]) for i, (name, title) in enumerate([
                  ('市场研究', '整理市场观察'), ('内容创作', '整理选题提纲'), ('示例工程', '检查页面布局')])]
payload = dict(updated_at=stamp, tasks=tasks,
               projects=[dict(id=str(i), name=t['project']) for i,t in enumerate(tasks)],
               sections=[dict(id='section-'+str(i), name=name, items=[dict(kind='project',id=str(i))])
                         for i,name in enumerate(['投资', '创作', '项目'])])
p = destination / 'ios-watch/Sources/Shared/TaskDashboard.swift'
p.write_text(p.read_text()+'''
#if canImport(SwiftUI)
extension TaskDashboardModel {
    static func gallery() -> TaskDashboardModel {
        let model = TaskDashboardModel()
        model.snapshot = try! JSONDecoder().decode(TaskDashboardSnapshot.self, from: Data(#"""
'''+json.dumps(payload,ensure_ascii=False)+'''
"""#.utf8))
        return model
    }
}
struct SidebarGallery: View {
    @StateObject private var model = TaskDashboardModel.gallery()
    var body: some View {
        NavigationStack { TaskListView(model: model, base: "https://demo.invalid", token: "") }
            .preferredColorScheme(.dark)
    }
}
#endif
''')
for app, filename, original in [('iPhoneApp','QuotaPhoneApp.swift','ContentView()'), ('WatchApp','QuotaWatchApp.swift','WatchContentView()')]:
    p = destination / 'ios-watch/Sources' / app / filename
    p.write_text(p.read_text().replace(original,'SidebarGallery()',1))
print(destination)
