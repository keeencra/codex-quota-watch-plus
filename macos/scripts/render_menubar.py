"""Render the real attributed menu titles with fictional balances, without account access."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
out = root / 'build/menubar'
out.mkdir(parents=True, exist_ok=True)
source = (root / 'main.swift').read_text().split('let app = NSApplication.shared')[0]
# Keep the pending preview reproducible against the current release source.
if 'enum MenuBarSummary' not in source:
    source += 'extension DeepSeekBalance {\n    // Prefer a funded CNY account, then another funded currency; never add currencies.\n    var menuBarAmount: String {\n        let positive = balance_infos.filter { (Decimal(string: $0.total_balance) ?? 0) > 0 }\n        let entry = positive.first { $0.currency == "CNY" } ?? positive.first\n            ?? balance_infos.first { $0.currency == "CNY" } ?? balance_infos.first\n        return entry?.display ?? "—"\n    }\n}\n\nenum MenuBarSummary {\n    static func title(codex: String, balance: DeepSeekBalance?) -> NSAttributedString {\n        let text = NSMutableAttributedString(string: codex, attributes: [\n            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)\n        ])\n        text.append(NSAttributedString(string: " · ", attributes: [\n            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor\n        ]))\n        text.append(NSAttributedString(string: "DS " + (balance?.menuBarAmount ?? "—"), attributes: [\n            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)\n        ]))\n        return text\n    }\n}\n'
source += r'''
let app = NSApplication.shared
app.appearance = NSAppearance(named: .darkAqua)
let balance = DeepSeekBalance(is_available: true, balance_infos: [
    .init(currency: "USD", total_balance: "0.00", granted_balance: "0.00", topped_up_balance: "0.00"),
    .init(currency: "CNY", total_balance: "88.88", granted_balance: "0.00", topped_up_balance: "88.88")])
assert(balance.menuBarAmount == "¥88.88")
let usd = DeepSeekBalance(is_available: true, balance_infos: [
    .init(currency: "CNY", total_balance: "0.00", granted_balance: "0.00", topped_up_balance: "0.00"),
    .init(currency: "USD", total_balance: "12.34", granted_balance: "0.00", topped_up_balance: "12.34")])
assert(usd.menuBarAmount == "$12.34")
assert(DeepSeekBalance(is_available: false, balance_infos: []).menuBarAmount == "—")
let image = NSImage(size: NSSize(width: 540, height: 144))
image.lockFocus()
NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 540, height: 144)).fill()
for (index, codex) in ["Pro 周73%", "Plus 5h42% 周73%"].enumerated() {
    let title = MenuBarSummary.title(codex: codex, balance: balance)
    let old = NSAttributedString(string: index == 0 ? "  Pro  ·  周 73%   |   DeepSeek ¥88.88 / $0.00" : "  Plus  ·  5h 42%  /  周 73%   |   DeepSeek ¥88.88 / $0.00", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    print("\(codex): title \(ceil(title.size().width)) pt, previous approximately \(ceil(old.size().width)) pt (excluding unchanged icon/padding)")
    let whiteTitle = NSMutableAttributedString(attributedString: title)
    whiteTitle.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location:0,length:whiteTitle.length))
    let y = CGFloat(94 - index * 46)
    MenuBarQuotaGlyph.image(short: index == 0 ? nil : 42, total: 73).draw(in: NSRect(x: 28, y: y-2, width: 16, height: 18))
    whiteTitle.draw(at: NSPoint(x: 49, y: y))
}
NSAttributedString(string: "AppKit · fictional demo · actual title size", attributes: [.font: NSFont.systemFont(ofSize:10), .foregroundColor: NSColor.gray]).draw(at:NSPoint(x:28,y:17))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/assets/v3.1.0-menubar.png"))
'''
p = out / 'main.swift'
p.write_text(source)
subprocess.run(['swift', str(p)], cwd=root, check=True)
