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
let timestamp = ISO8601DateFormatter().date(from: "2026-09-14T07:59:00Z")!
let shanghai = TimeZone(identifier: "Asia/Shanghai")!
let persian = DateFormatter()
persian.calendar = Calendar(identifier: .persian)
persian.timeZone = shanghai
persian.dateFormat = "MM-dd HH:mm"
assert(persian.string(from: timestamp) == "06-23 15:59")
assert(QuotaTimestamp.label(timestamp, timeZone: shanghai) == "09-14 15:59")
assert(QuotaTimestamp.label(timestamp, timeZone: TimeZone(secondsFromGMT: 0)!) == "09-14 07:59")
assert(QuotaTimestamp.label(nil) == "待更新")
print("PASS: Gregorian timestamps under Persian system calendar, timezone and missing date")
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
func menuBalance(_ entries: [(String, String)]) -> DeepSeekBalance {
    DeepSeekBalance(is_available: true, balance_infos: entries.map {
        DeepSeekBalance.Entry(currency: $0.0, total_balance: $0.1, granted_balance: "0", topped_up_balance: $0.1)
    })
}
assert(menuBalance([("USD", "20.00"), ("CNY", "88.88")]).menuBarAmount == "¥88.88 / $20.00")
assert(menuBalance([("CNY", "88.88"), ("USD", "0.00")]).menuBarAmount == "¥88.88")
assert(menuBalance([("CNY", "0.00"), ("USD", "20.00")]).menuBarAmount == "$20.00")
assert(menuBalance([("CNY", "0.00"), ("USD", "0.00")]).menuBarAmount == "¥0.00 / $0.00")
assert(menuBalance([]).menuBarAmount == "—")
assert(MenuBarSummary.title(codex: "Pro 周16%", balance: menuBalance([("CNY", "88.88"), ("USD", "20.00")])).string == "Pro 周16% · DS ¥88.88 / $20.00")
print("PASS: menu bar dual currency, CNY only, USD only, zero, empty and final title")

let sessionRoot = temp.appendingPathComponent(".codex/sessions")
try! FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
func event(_ stamp: String, _ input: Int, _ output: Int, _ lastInput: Int, _ lastOutput: Int) -> String {
    return "{\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),\"cached_input_tokens\":80},\"last_token_usage\":{\"input_tokens\":\(lastInput),\"output_tokens\":\(lastOutput)}}}}\n"
}
let beforeMidnight = event("2026-09-13T15:59:00Z", 100, 10, 100, 10)
let afterMidnight = event("2026-09-13T16:01:00Z", 140, 15, 40, 5)
let unchanged = event("2026-09-13T16:02:00Z", 140, 15, 40, 5)
let reset = event("2026-09-13T16:03:00Z", 20, 2, 20, 2)
let fixture = beforeMidnight + afterMidnight + unchanged + reset
let log = sessionRoot.appendingPathComponent("test.jsonl")
try! fixture.write(to: log, atomically: true, encoding: .utf8)
try! fixture.write(to: sessionRoot.appendingPathComponent("duplicate.jsonl"), atomically: true, encoding: .utf8)
let dailyReader = DailyTokenReader(home: temp)
let daily = dailyReader.read(now: timestamp, zone: shanghai)
assert(daily.days.count == 7 && daily.days[5].codex == 110 && daily.days[6].codex == 67)
assert(daily.days[0].codex == 0 && daily.codexStatus == nil)
assert(daily.deepSeekStatus == "未找到本机记录")
let cached = dailyReader.read(now: timestamp, zone: shanghai)
assert(cached.days.map(\.codex) == daily.days.map(\.codex))
let extra = event("2026-09-14T06:00:00Z", 30, 5, 10, 3)
try! (fixture + extra).write(to: log, atomically: true, encoding: .utf8)
assert(dailyReader.read(now: timestamp, zone: shanghai).days[6].codex == 80)

let append = try! FileHandle(forWritingTo: log); try! append.seekToEnd()
let tail = Data(event("2026-09-14T06:02:00Z", 40, 7, 10, 2).utf8)
try! append.write(contentsOf: tail.prefix(tail.count / 2))
assert(dailyReader.read(now: timestamp, zone: shanghai).days[6].codex == 80)
try! append.write(contentsOf: tail.suffix(tail.count - tail.count / 2)); try! append.close()
assert(dailyReader.read(now: timestamp, zone: shanghai).days[6].codex == 92)
let db = temp.appendingPathComponent(".codex/tools/deepseek/state/usage.sqlite3")
try! FileManager.default.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)
let sql = Process(); sql.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
sql.arguments = [db.path, "CREATE TABLE calls(started TEXT,total_tokens INTEGER,prompt_tokens INTEGER,completion_tokens INTEGER); INSERT INTO calls VALUES('2026-09-13T23:59:00+08:00',110,100,10),('2026-09-14T00:01:00+08:00',NULL,40,5),('2026-09-14T01:00:00+08:00',NULL,NULL,NULL),('2026-09-15T00:01:00+08:00',999,900,99);"]
try! sql.run(); sql.waitUntilExit(); assert(sql.terminationStatus == 0)
let withDeepSeek = dailyReader.read(now: timestamp, zone: shanghai)
assert(withDeepSeek.days[5].deepSeek == 110 && withDeepSeek.days[6].deepSeek == 45)
assert(withDeepSeek.deepSeekStatus == "部分调用缺少用量")
assert(DailyTokenUsage.number(1_200_000_000) == "1.20B")
print("PASS: daily tokens — midnight, Gregorian days, cached input, duplicates, reset, cache invalidation, SQLite totals/fallback/missing/future records")
print("PASS: 7 scenarios — Pro, Plus, empty, invalid, reversed, multiple currencies, invalid balance")
'''
p=out/'main.swift';p.write_text(source)
subprocess.run(['swiftc','-framework','AppKit',str(p),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
