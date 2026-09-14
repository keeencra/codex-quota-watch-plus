from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
out = root / 'build/daily-gallery'
out.mkdir(parents=True, exist_ok=True)
source = (root / 'main.swift').read_text().split('let app = NSApplication.shared')[0]
source += r'''
let app = NSApplication.shared
let now = DailyTokenReader.date("2026-09-14T07:59:00Z")!
var daily = DailyTokenUsage.empty(now: now)
daily.codexStatus = nil; daily.deepSeekStatus = nil
for i in 0..<7 { daily.days[i].codex = [180000,520000,390000,1100000,670000,240000,830000][i]; daily.days[i].deepSeek = [1200,0,28000,3700,5800,11000,6200][i] }
let week = AccountUsageWindow(remainingPercent: 73, usedPercent: 27, windowLabel: "1周", resetsAt: now.addingTimeInterval(86400), durationMinutes: 10080)
let short = AccountUsageWindow(remainingPercent: 42, usedPercent: 58, windowLabel: "5小时", resetsAt: now.addingTimeInterval(7200), durationMinutes: 300)
let balance = DeepSeekBalance(is_available: true, balance_infos: [.init(currency: "CNY", total_balance: "88.88", granted_balance: "0", topped_up_balance: "88.88"), .init(currency: "USD", total_balance: "20.00", granted_balance: "0", topped_up_balance: "20.00")])
let threads = (1...8).map { index in ThreadUsage(id: "demo-\(index)", title: "演示项目 · \(index == 1 ? "优化移动端任务列表中的长标题展示与项目分组，检查刷新后的导航状态" : "验证组件布局与数据同步")", tokens: index * 123456, model: "demo-model", updatedAtMs: Int64(now.timeIntervalSince1970 * 1000)) }
for plus in [false, true] {
    let account = AccountUsage(shortWindow: plus ? short : nil, totalWindow: week, resetCredits: ResetCredits(availableCount: 2, expirations: [now.addingTimeInterval(86400), now.addingTimeInterval(172800)]), planType: plus ? "plus" : "pro", lastSuccessAt: now)
    let snapshot = AppSnapshot(accountUsage: account, threadUsage: UsageSnapshot(current: threads.first, recent: threads, totalRecentTokens: threads.reduce(0) { $0 + $1.tokens }, checkedAt: now, error: nil), checkedAt: now, nextRefreshAt: now.addingTimeInterval(60), accountError: nil, dailyTokens: daily)
    let controller = QuotaPanelController()
    controller.panelHeight = 760
    controller.setActions([("刷新", {}), ("添加小组件", {}), ("手机与手表", {}), ("关于码伴", {}), ("回到顶部", {}), ("退出", {})])
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 368, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = controller
    func dashboard() -> QuotaDashboardView { QuotaDashboardView(snapshot: snapshot, balance: balance, error: nil, date: now) }
    controller.update(dashboard())
    controller.view.layoutSubtreeIfNeeded()
    let scroll = controller.view.subviews.compactMap { $0 as? NSScrollView }.first!
    for (index, title) in ["总览", "每日明细", "任务"].enumerated() {
        let button = controller.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == title }!
        button.performClick(nil)
        let offset = scroll.contentView.bounds.origin.y
        controller.update(dashboard())
        assert(abs(scroll.contentView.bounds.origin.y - offset) < 1, "refresh must retain scroll offset")
        if index > 0 { assert(offset > 0, "navigation must scroll to the requested section") }
        controller.view.layoutSubtreeIfNeeded()
        let view = controller.view
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let name = ["plus", "detail", "tasks"][index]
        let path = plus ? "../docs/assets/v3.3.0-daily-tokens-\(name).png" : "build/daily-gallery/pro-\(name).png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
    controller.scrollToTop()
    assert(scroll.contentView.bounds.origin.y == 0)
}
print("PASS: unified panel navigation, scroll preservation on refresh and return to top; fictional native renders")
'''
p = out / 'main.swift'; p.write_text(source)
subprocess.run(['swift', str(p)], cwd=root, check=True)
