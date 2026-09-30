"""Prepare isolated, synthetic Antigravity UI builds; never touches device pairing."""
from pathlib import Path
import shutil
import tempfile

root = Path(__file__).resolve().parents[2]
out = Path(tempfile.mkdtemp(prefix='codecompanion-ag-gallery-'))
for name in ('ios-watch', 'shared-widgets', 'macos'):
    shutil.copytree(root / name, out / name,
                    ignore=shutil.ignore_patterns('.build', 'build', 'xcuserdata', '.git'))
for path, app in [('iPhoneApp/QuotaPhoneApp.swift', 'QuotaPhoneApp'),
                  ('WatchApp/QuotaWatchApp.swift', 'QuotaWatchApp')]:
    (out / 'ios-watch/Sources' / path).write_text('''import SwiftUI
@main struct ''' + app + ''': App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                AntigravityStatusView(base: "", token: "", demo: true)
            }
        }
    }
}
''')
# The phone ContentView references this production type. Keep a no-op stub only
# in this temporary gallery, whose root never initializes connectivity/services.
phone = out / 'ios-watch/Sources/iPhoneApp/QuotaPhoneApp.swift'
phone.write_text(phone.read_text() + '''
enum BackgroundRefreshResult { case success(WatchSnapshot); case failure(String) }
enum BackgroundRefreshService {
 static func scheduleIfEnabled() {}
 static func cancel() {}
 static func fetchAndSync(macURL: String, token: String) async throws -> WatchSnapshot { .placeholder }
 static func runWatchRequestedRefresh() async -> BackgroundRefreshResult { .failure("Offline gallery") }
}
''')
print(out)
