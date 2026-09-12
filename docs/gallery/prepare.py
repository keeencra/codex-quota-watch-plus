# coding: utf-8
from pathlib import Path
import shutil,json,re
r=Path.cwd(); dst=Path('/tmp/codecompanion-v3-gallery');dst.mkdir(exist_ok=True)
shutil.copytree(r/'ios-watch',dst/'ios-watch',dirs_exist_ok=True,ignore=shutil.ignore_patterns('.build','build','xcuserdata'))
# Synthetic fixtures only. All gallery requests are intercepted before URLSession.
snapshot=json.loads((r/'docs/examples/watch-response.json').read_text());stamp='2026-09-13T01:00:00Z';snapshot['updated_at']=stamp
snapshot['codex'].update(plan_type='pro',status='ok',today_tokens=128400,today_input_tokens=62400,today_output_tokens=18000,today_cache_tokens=48000)
snapshot['codex']['buckets']=[dict(id='codex:weekly',label='Codex',remaining_percent=72,used_percent=28,reset_in='3d 6h',window='7d',status='ok')]
snapshot['codex']['hourly']=[{'hour':h,'tokens':v} for h,v in enumerate([1000,4200,12800,5000,6000,2000,9500,21000,19000,14700,20200,13000])]
snapshot['deepseek']={'status':'ok','updated_at':stamp,'is_available':True,'balance_infos':[{'currency':'CNY','total_balance':'128.5600','granted_balance':'8.5600','topped_up_balance':'120.0000'},{'currency':'USD','total_balance':'3.2500','granted_balance':'0.0000','topped_up_balance':'3.2500'}]}
snapshot['notifications']={'enabled':True,'provider':'bark','server':'https://api.day.app','topic':'demo-topic','pending_count':0,'last_delivery_at':stamp}
tasks=[]
for i,(title,project,status,phase) in enumerate([('优化移动端首页','产品开发','running','正在执行工具'),('整理更新说明','项目文档','running','正在整理回复'),('验证导航修复','产品开发','needs_approval','等待操作确认'),('检查小组件刷新','产品开发','finished','本轮已结束')]):
 tasks.append(dict(id='demo-task-'+str(i),title=title,project=project,project_name=project,status=status,phase=phase,updated_at=stamp,started_at=stamp,stale=False,recent=[dict(text=t,at=stamp) for t in ['正在分析任务','正在检查项目文件',phase]]))
request=dict(id='d'*32,nonce='gallery-demo-only-not-a-real-token',fingerprint='gallery-demo-only-not-a-real-token',project='产品开发 · 验证导航修复',tool='shell',details='/usr/bin/true',expires=0,status='pending',decision=None)
fixtures={'snapshot':snapshot,'tasks':{'updated_at':stamp,'tasks':tasks},'request':request}
(r/'docs/gallery/fixtures.json').write_text(json.dumps(fixtures,ensure_ascii=False,indent=2)+'\n')
code='\nenum GalleryFixture {\n static let screen = ProcessInfo.processInfo.environment["GALLERY_SCREEN"] ?? "home"\n static let plan = ProcessInfo.processInfo.environment["GALLERY_PLAN"] ?? "pro"\n static let balanceMode = ProcessInfo.processInfo.environment["GALLERY_BALANCE"] ?? "ok"\n'
for k,v in fixtures.items():code+=f' static let raw{k.capitalize()} = Data(#"""\n{json.dumps(v,ensure_ascii=False)}\n"""#.utf8)\n'
code+='''
 static var snapshot: Data {
  var value = try! JSONSerialization.jsonObject(with: rawSnapshot) as! [String:Any]
  var codex = value["codex"] as! [String:Any]; codex["plan_type"] = plan
  if plan == "plus" { var buckets = codex["buckets"] as! [[String:Any]]; buckets.insert(["id":"codex:primary","label":"Codex","window":"5h","remaining_percent":85,"used_percent":15,"reset_in":"2h","status":"ok"],at:0); codex["buckets"] = buckets }
  value["codex"] = codex
  if balanceMode != "ok" { value["deepseek"] = ["status":balanceMode,"balance_infos":[],"error":"余额查询失败，请稍后刷新。"] }
  return try! JSONSerialization.data(withJSONObject:value)
 }
 static var watch: WatchSnapshot { try! JSONDecoder().decode(WatchSnapshot.self,from:snapshot) }
 static var tasks: Data { screen == "tasks-empty" ? Data(#"{"updated_at":"2026-09-13T01:00:00Z","tasks":[]}"#.utf8) : rawTasks }
 static var request: Data { var r = try! JSONSerialization.jsonObject(with:rawRequest) as! [String:Any];r["expires"] = Date().timeIntervalSince1970 + 600;return try! JSONSerialization.data(withJSONObject:r) }
 static var approvals: Data { let r = try! JSONSerialization.jsonObject(with: request);return try! JSONSerialization.data(withJSONObject:["enabled":true,"requests":screen == "approvals-empty" ? [] : [r]]) }
}
'''
def replace_body(s,marker,body):
 a=s.index(marker);start=s.index('{',a);depth=1;i=start+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[:start+1]+'\n'+body+'\n'+s[i-1:]
p=dst/'ios-watch/Sources/Shared/UsageClient.swift';s=p.read_text();s=replace_body(s,'    public func fetchCompact(', '        return GalleryFixture.watch')
a=s.index('        guard let url = endpoint(base: base, path: path)');b=s.index('\n    }',a)
s=s[:a]+'''        if body != nil { throw UsageClientError.badResponse(409) }
        return path == "/tasks" ? GalleryFixture.tasks : path == "/approvals" ? GalleryFixture.approvals : GalleryFixture.request'''+s[b:]
s+='''
struct GalleryApprovalDetail: View {
 var body: some View { ApprovalDetailView(base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token",initial:try! JSONDecoder().decode(RemoteApproval.self,from:GalleryFixture.request)) }
}
'''+code;p.write_text(s)
p=dst/'ios-watch/Sources/Shared/UsageModels.swift';s=p.read_text();s=replace_body(s,'    public func load() -> WatchSnapshot','        GalleryFixture.watch');s=replace_body(s,'    public func load() -> WatchAgentConfig?', '        WatchAgentConfig.make(macURL:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token")');p.write_text(s)
# Render exact existing destinations, extracted from the production phone view.
p=dst/'ios-watch/Sources/iPhoneApp/ContentView.swift';s=p.read_text()
qa=s.index('                        List {',s.index('Section("官方额度")')-65);qb=s.index('\n                    } label:',qa);quota=s[qa:qb]
aa=s.index('                        List {',s.index('Section("更多")'));ab=s.index('\n                    } label:',aa);about=s[aa:ab]
# Stable section IDs allow deterministic screenshots of actual settings Form rows.
for title,key in [('连接与同步','settings'),('任务提醒','notifications'),('更多','diagnostics')]:
 a=s.index('Section("'+title+'")');start=s.index('{',a);depth=1;i=start+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 s=s[:i]+'.id("'+key+'")'+s[i:]
s=s.replace('Form {','ScrollViewReader { proxy in\n            Form {',1).replace('            .navigationTitle("码伴")','            .task { if GalleryFixture.screen != "home" { try? await Task.sleep(nanoseconds: 300_000_000); proxy.scrollTo(GalleryFixture.screen,anchor:.top) } }\n            }\n            .navigationTitle("码伴")',1)
for title in ['Mac 连接设置','通知设置与状态','连接诊断']:s=s.replace('DisclosureGroup("'+title+'")','DisclosureGroup("'+title+'", isExpanded: .constant(true))')
s=s.replace('private var macURL: String = "http://127.0.0.1:8787"','private var macURL: String = "https://demo.invalid"')
s+='\nextension ContentView {\n var galleryQuota: some View {\n'+quota+'\n }\n var galleryAbout: some View {\n'+about+'\n }\n}\n'
s+='''
struct GalleryPhoneRoot: View {
 @StateObject var model = TaskDashboardModel()
 var body: some View {
  Group {
   switch GalleryFixture.screen {
   case "home", "settings", "notifications", "diagnostics": ContentView()
   default: NavigationStack {
    switch GalleryFixture.screen {
    case "quota": ContentView().galleryQuota
    case "about": ContentView().galleryAbout
    case "tasks", "tasks-empty": TaskListView(model:model,base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token")
    case "task": TaskProgressView(id:"demo-task-0",model:model,base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token")
    case "approvals", "approvals-empty": ApprovalInboxView(base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token")
    case "approval": GalleryApprovalDetail()
    case "balance": DeepSeekBalanceView(balance:GalleryFixture.watch.deepseek)
    case "widgets": GalleryWidgets()
    default: ContentView()
    }
   }
   }
  }.preferredColorScheme(.dark).task { await model.refresh(base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token") }
 }
}
'''
widget=(r/'ios-watch/Sources/WidgetExtension/CodingQuotaWidget.swift').read_text().split('@main\nstruct CodingQuotaWidgetMain')[0].replace('@Environment(\\.widgetFamily) private var family','var family: WidgetFamily = .systemSmall')
s+='\n'+widget+'''
struct GalleryWidgets: View {
 var body: some View {
  VStack(alignment:.leading,spacing:18) {
   Text("码伴 · \\(GalleryFixture.plan.capitalized)").font(.title2.bold())
   Text(GalleryFixture.balanceMode == "not_configured" ? "Codex 专用布局" : "Codex＋DeepSeek 布局").foregroundStyle(.secondary)
   Text("模拟器宿主 · 虚构演示数据").font(.caption)
   CodingQuotaWidgetView(family:.systemSmall,entry:CodingQuotaWidgetEntry(date:Date(),snapshot:GalleryFixture.watch)).frame(width:160,height:160).clipShape(RoundedRectangle(cornerRadius:22))
   CodingQuotaWidgetView(family:.systemMedium,entry:CodingQuotaWidgetEntry(date:Date(),snapshot:GalleryFixture.watch)).frame(width:344,height:160).clipShape(RoundedRectangle(cornerRadius:22))
   CodingQuotaWidgetView(family:.systemMedium,entry:CodingQuotaWidgetEntry(date:Date(),snapshot:GalleryFixture.watch,refreshFailed:true)).frame(width:344,height:160).clipShape(RoundedRectangle(cornerRadius:22))
  }.padding().frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(white:0.06))
 }
}
''';p.write_text(s)
p=dst/'ios-watch/Sources/iPhoneApp/QuotaPhoneApp.swift';p.write_text(p.read_text().replace('ContentView()','GalleryPhoneRoot()',1))
p=dst/'ios-watch/Sources/WatchApp/WatchContentView.swift';s=p.read_text();s+='''
struct GalleryWatchRoot: View {
 @StateObject var model = TaskDashboardModel()
 var body: some View {
  Group {
   if GalleryFixture.screen == "home" { WatchContentView() }
   else { NavigationStack {
    switch GalleryFixture.screen {
    case "quota": CodexQuotaPage(snapshot:GalleryFixture.watch)
    case "today": LocalTodayPage(usage:GalleryFixture.watch.codex)
    case "tasks", "tasks-empty": TaskListView(model:model,base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token")
    case "task": TaskProgressView(id:"demo-task-0",model:model,base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token")
    case "approvals", "approvals-empty": ApprovalInboxView(base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token")
    case "approval": GalleryApprovalDetail()
    default: DeepSeekBalanceView(balance:GalleryFixture.watch.deepseek)
    }
   } }
  }.task { await model.refresh(base:"https://demo.invalid",token:"gallery-demo-only-not-a-real-token") }
 }
}
''';p.write_text(s)
p=dst/'ios-watch/Sources/WatchApp/QuotaWatchApp.swift';p.write_text(p.read_text().replace('WatchContentView()','GalleryWatchRoot()',1))
print('Prepared isolated gallery:',dst)

from pathlib import Path
p=Path('/tmp/codecompanion-v3-gallery/ios-watch/Sources/iPhoneApp/ContentView.swift');s=p.read_text()
for title,key in [('连接与同步','settings'),('任务提醒','notifications'),('更多','diagnostics')]:
 a=s.index('Section("'+title+'")');start=s.index('{',a);depth=1;i=start+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 block=s[a:i]
 s+='\nextension ContentView { var gallery'+key.capitalize()+': some View { Form { '+block+' }.navigationTitle("'+title+'") } }\n'
s=s.replace('case "home", "settings", "notifications", "diagnostics": ContentView()','case "home": ContentView()')
s=s.replace('case "quota": ContentView().galleryQuota','case "settings": ContentView().gallerySettings\n    case "notifications": ContentView().galleryNotifications\n    case "diagnostics": ContentView().galleryDiagnostics\n    case "quota": ContentView().galleryQuota')
p.write_text(s)
p=Path('/tmp/codecompanion-v3-gallery/ios-watch/Sources/Shared/TaskDashboard.swift');s=p.read_text().replace('@Published public private(set) var snapshot: TaskDashboardSnapshot?','@Published public private(set) var snapshot: TaskDashboardSnapshot? = try! JSONDecoder().decode(TaskDashboardSnapshot.self, from: GalleryFixture.tasks)').replace('@Published public private(set) var approvalCount: Int?','@Published public private(set) var approvalCount: Int? = GalleryFixture.screen == "approvals-empty" ? 0 : 1').replace('var approvalMessage = "连接中"','var approvalMessage = "查看并处理"');p.write_text(s)
