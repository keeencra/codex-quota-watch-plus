from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
out = root/'build/tests'; out.mkdir(parents=True,exist_ok=True)
source=(root/'main.swift').read_text().split('let app = NSApplication.shared')[0]
source+=r'''
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try! FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
assert(DeepSeekBalanceReader.configuredKey(environment: [:], home: temp) == "")
let legacyKey = temp.appendingPathComponent(".codex/secrets/deepseek-api-key")
let sharedKey = temp.appendingPathComponent("Library/Application Support/CodexQuotaWatch/deepseek-api-key")
for path in [legacyKey, sharedKey] { try! FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true) }
try! "legacy-fixture".write(to: legacyKey, atomically: true, encoding: .utf8)
assert(DeepSeekBalanceReader.configuredKey(environment: [:], home: temp) == "legacy-fixture")
try! "shared-fixture\n".write(to: sharedKey, atomically: true, encoding: .utf8)
assert(DeepSeekBalanceReader.configuredKey(environment: [:], home: temp) == "shared-fixture")
assert(DeepSeekBalanceReader.configuredKey(environment: ["DEEPSEEK_API_KEY":"env-fixture"], home: temp) == "env-fixture")
assert(DeepSeekBalanceReader.configuredKey(environment: ["DEEPSEEK_API_KEY":"  "], home: temp) == "shared-fixture")
print("PASS: shared key lookup, legacy fallback, environment override, whitespace and missing configuration")
let reader = AccountUsageReader()
func parse(_ limit: String, modern: Bool = true) -> AccountUsage? {
    let payload = modern ? "\"rateLimitsByLimitId\":{\"codex\":\(limit)}" : "\"rateLimits\":\(limit)"
    return reader.parseUsageResponse("{\"id\":2,\"result\":{\(payload)}}")
}
let week = "{\"usedPercent\":27,\"windowDurationMins\":10080}"
let short = "{\"usedPercent\":58,\"windowDurationMins\":300}"
let pro = parse("{\"primary\":\(week),\"secondary\":null,\"planType\":\"prolite\"}")!
assert(pro.shortWindow == nil && pro.totalWindow?.remainingPercent == 73)
let plus = parse("{\"primary\":\(short),\"secondary\":\(week)}", modern:false)!
assert(plus.shortWindow?.remainingPercent == 42 && plus.totalWindow?.remainingPercent == 73)
assert(parse("{\"primary\":null,\"secondary\":null}") == nil)
assert(parse("{\"primary\":{\"windowDurationMins\":300}}") == nil)
let reversed = parse("{\"primary\":\(week),\"secondary\":\(short)}")!
assert(reversed.shortWindow?.durationMinutes == 300)
let deep = Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"88.88","granted_balance":"8.88","topped_up_balance":"80.00"},{"currency":"USD","total_balance":"0.00","granted_balance":"0.00","topped_up_balance":"0.00"}]}"#.utf8)
let balance = try! JSONDecoder().decode(DeepSeekBalance.self,from:deep)
assert(balance.balance_infos.map { $0.display } == ["¥88.88", "$0.00"])
assert((try? JSONDecoder().decode(DeepSeekBalance.self,from:Data("{}".utf8))) == nil)
print("PASS: 7 scenarios — Pro, Plus, empty, invalid, reversed, multiple currencies, invalid balance")
'''
p=out/'main.swift';p.write_text(source)
subprocess.run(['swiftc','-framework','AppKit',str(p),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
