from pathlib import Path
import subprocess
import os
# Use a new prefix for unpublished galleries; never overwrite published images.
prefix = os.environ.get('WIDGET_GALLERY_PREFIX', 'preview-widget')
root = Path(__file__).resolve().parents[1]
out = root/'build/widget-gallery'
out.mkdir(parents=True, exist_ok=True)
source = (root/'Sources/Widget/QuotaWidget.swift').read_text().split('#if os(macOS)\nstruct WidgetContent')[0]
source += r'''
@main struct Gallery {
    @MainActor static func main() {
        var pro = WidgetSnapshot.preview
        pro.plan = "Pro"
        pro.windows = [pro.windows[1]]
        var unconfigured = pro
        unconfigured.balances = []
        unconfigured.balanceError = "未配置 API Key"
        var manyCredits = WidgetSnapshot.preview
        manyCredits.resetCredits = .init(availableCount: 4, expirations: (1...4).map { Date().addingTimeInterval(Double($0) * 86400) })
        for (name, data, small) in [("small-pro", pro, true), ("small-plus", WidgetSnapshot.preview, true), ("medium", WidgetSnapshot.preview, false), ("empty", WidgetSnapshot.empty, false), ("large", WidgetSnapshot.preview, false), ("large-pro", pro, false), ("large-unconfigured", unconfigured, false), ("large-many-credits", manyCredits, false)] {
            if CommandLine.arguments.count > 1 && CommandLine.arguments[1] != name { continue }
            let view = QuotaWidgetView(entry: .init(date: Date(), snapshot: data), compact: small, expanded: name.hasPrefix("large"))
                .padding(16).frame(width: small ? 170 : 364, height: name.hasPrefix("large") ? 382 : 170)
                .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 22))
                .environment(\.colorScheme, .dark)
            _ = NSApplication.shared
            let host = NSHostingView(rootView: view)
            let size = NSSize(width: small ? 170 : 364, height: name.hasPrefix("large") ? 382 : 170)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "../docs/assets/__GALLERY_PREFIX__-\(name).png"))
        }
    }
}
'''
source = source.replace('__GALLERY_PREFIX__', prefix)
p=out/'Gallery.swift';p.write_text(source)
subprocess.run(['swiftc','-D','WIDGET_GALLERY','-parse-as-library','-target',subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macos14.0','-framework','SwiftUI','-framework','WidgetKit',str(root/'Sources/Shared/WidgetSnapshot.swift'),str(root.parent/'shared-widgets/WidgetAppearance.swift'),str(p),'-o',str(out/'gallery')],check=True)
for name in ['small-pro','small-plus','medium','empty','large','large-pro','large-unconfigured','large-many-credits']:
    subprocess.run([str(out/'gallery'), name],cwd=root,check=True)
print('Rendered actual SwiftUI widget views with fictional data; not desktop screenshots')
