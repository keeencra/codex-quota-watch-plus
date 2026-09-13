from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
out = root/'build/classic-gallery'
out.mkdir(parents=True, exist_ok=True)
source = r'''
import SwiftUI
import WidgetKit
@main struct Gallery {
    @MainActor static func main() throws {
        var pro = WidgetSnapshot.preview
        pro.plan = "Pro"
        pro.windows = [pro.windows[1]]
        pro.recentTokens = 128400
        var without = pro
        without.balances = []
        without.balanceError = "未配置 API Key"
        for (name, data, family) in [("small-pro", pro, WidgetFamily.systemSmall), ("medium-pro", pro, .systemMedium), ("medium-plus", WidgetSnapshot.preview, .systemMedium), ("small-plus", WidgetSnapshot.preview, .systemSmall), ("medium-no-deepseek", without, .systemMedium)] {
            if CommandLine.arguments.count > 1 && CommandLine.arguments[1] != name { continue }
            let entry = MacClassicProvider().classicEntry(data)
            precondition(entry.snapshot != nil)
            precondition(entry.snapshot?.deepseek != nil)
            let view = CodingQuotaWidgetView(familyOverride: family, entry: entry)
                .environment(\.colorScheme, .dark)
                .frame(width: family == .systemSmall ? 170 : 364, height: 170)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/assets/v3.1.0-classic-\(name).png"))
        }
    }
}
'''
p=out/'Gallery.swift';p.write_text(source)
files=[root.parent/'shared-widgets/WidgetAppearance.swift',root/'Sources/Shared/WidgetSnapshot.swift',root/'Sources/Widget/ClassicWidget.swift',root.parent/'shared-widgets/ClassicQuotaView.swift',root.parent/'ios-watch/Sources/Shared/UsageModels.swift',p]
subprocess.run(['swiftc','-parse-as-library','-target',subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macos14.0','-framework','SwiftUI','-framework','WidgetKit',*map(str,files),'-o',str(out/'gallery')],check=True)
for name in ['small-pro','medium-pro','small-plus','medium-plus','medium-no-deepseek']:
    subprocess.run([str(out/'gallery'), name],cwd=root,check=True)
print('Rendered shared classic views using fictional data')
