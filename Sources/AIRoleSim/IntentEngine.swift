import Foundation
import UserNotifications

// MARK: - 通用意图检测 + 数据预取
// 不依赖模型自觉：用户消息明确命中意图时，引擎自动执行对应工具，
// 把真实数据以"系统注入"的方式放进本轮上下文。所有模型（含不支持
// function calling 的）都能基于真实数据回答。

struct PrefetchedData {
    var toolName: String
    var result: String
    /// 生图时保存的图片文件名
    var imageName: String?
}

/// 图片落盘（与 AppStore.imagesDir 同目录）
enum ImageStore {
    static var dir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("AIRoleSim/images", isDirectory: true)
    }

    static func save(_ data: Data) -> String? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        guard (try? data.write(to: dir.appendingPathComponent(name), options: .atomic)) != nil else { return nil }
        return name
    }
}

enum IntentEngine {

    enum Action {
        case weather(city: String)
        case news
        case musicPlay(title: String, artist: String?)
        case musicStop
        case time
        case calculate(expression: String)
        case random(min: Int, max: Int, label: String)
        case search(query: String)
        case reminder(minutes: Double, text: String)
        case generateImage(prompt: String)
        case screen(mode: String?)
        case openURL(target: String)
        case clipboard
        case systemInfo
        case call(target: String)
    }

    /// 检测用户消息中的全部意图（可能多个，如"几点了+看新闻"）
    static func detect(_ text: String) -> [Action] {
        var actions: [Action] = []
        let han = text

        // 音乐停止
        if ["别放了", "停止播放", "暂停音乐", "把音乐停", "别播了", "停止音乐", "关掉音乐"].contains(where: { han.contains($0) }) {
            actions.append(.musicStop)
            return actions
        }
        // 音乐播放（书名号优先）
        if han.contains("歌") || han.contains("音乐") || han.contains("曲") || han.lowercased().contains("music") {
            let songs = extractMatches(han, pattern: "《([^》]+)》")
            if let first = songs.first {
                actions.append(.musicPlay(title: first, artist: nil))
            }
        }
        // 天气
        if han.contains("天气") || han.contains("气温") {
            if let city = extractCity(han) {
                actions.append(.weather(city: city))
            }
        }
        // 新闻
        if han.contains("新闻") || han.contains("资讯") || han.contains("热点") || han.contains("热搜") || han.contains("头条") {
            actions.append(.news)
        }
        // 时间
        if han.contains("几点") || han.contains("现在时间") || han.contains("今天几号") || han.contains("今天日期") || han.contains("星期几") || han.contains("几月几号") {
            actions.append(.time)
        }
        // 计算
        if let expr = extractMathExpression(han) {
            actions.append(.calculate(expression: expr))
        }
        // 随机数 / 骰子 / 硬币
        if han.contains("骰子") {
            actions.append(.random(min: 1, max: 6, label: "掷骰子"))
        } else if han.contains("硬币") {
            actions.append(.random(min: 0, max: 1, label: "抛硬币"))
        } else if han.contains("随机数") || han.contains("随便一个数") {
            let range = extractNumberRange(han) ?? (1, 100)
            actions.append(.random(min: range.0, max: range.1, label: "随机数"))
        }
        // 网页搜索
        if let q = extractSearchQuery(han) {
            actions.append(.search(query: q))
        }
        // 提醒
        if let r = extractReminder(han) {
            actions.append(.reminder(minutes: r.0, text: r.1))
        }
        // 生图
        if let p = extractImagePrompt(han) {
            actions.append(.generateImage(prompt: p))
        }
        // 屏幕
        if han.contains("我的屏幕") || han.contains("读一下屏幕") || han.contains("读取屏幕") || han.contains("截个屏") || han.contains("截屏") || han.contains("屏幕上是什么") || han.contains("看看屏幕") || han.contains("看一下屏幕") || han.contains("读屏幕") {
            actions.append(.screen(mode: nil))
        }
        // 剪贴板
        if han.contains("剪贴板") || han.contains("粘贴板") || han.contains("复制的东西") || han.contains("复制的文字") || han.contains("复制的内容") {
            actions.append(.clipboard)
        }
        // 打开网址
        if let target = extractOpenTarget(han) {
            actions.append(.openURL(target: target))
        }
        // 系统状态
        if han.contains("电脑状态") || han.contains("电量") || han.contains("电池") || han.contains("内存") || han.contains("系统信息") || han.contains("磁盘") || han.contains("硬盘") {
            actions.append(.systemInfo)
        }
        // 打电话
        if let target = extractCallTarget(han) {
            actions.append(.call(target: target))
        }
        return actions
    }

    /// "打电话给张三" / "呼叫 10086" / "拨打 13800138000"
    static func extractCallTarget(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?:打电话给|打电话|呼叫|拨打|打给)\\s*([^，。！？\\s]{2,20})") else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        let target = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.count >= 2 else { return nil }
        return String(target.prefix(20))
    }

    private static let siteMap: [(key: String, host: String)] = [
        ("b站", "www.bilibili.com"), ("哔哩哔哩", "www.bilibili.com"), ("bilibili", "www.bilibili.com"),
        ("知乎", "www.zhihu.com"), ("微博", "weibo.com"), ("淘宝", "www.taobao.com"),
        ("京东", "www.jd.com"), ("豆瓣", "www.douban.com"), ("github", "github.com"),
        ("youtube", "www.youtube.com"), ("网易云", "music.163.com"), ("百度", "www.baidu.com"),
        ("谷歌", "www.google.com"), ("抖音", "www.douyin.com"), ("小红书", "www.xiaohongshu.com")
    ]

    /// "帮我打开B站" / "打开 github.com" → 目标
    static func extractOpenTarget(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?:帮我打开|打开|开一下|访问)\\s*([^，。！？\\s]{2,40})") else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        var target = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.count >= 2 else { return nil }
        let lower = target.lowercased()
        // 站点映射
        for (key, host) in siteMap where lower.contains(key) {
            return host
        }
        // 直接是域名/URL
        if lower.hasPrefix("http") || lower.range(of: "^([\\w-]+\\.)+[a-z]{2,}", options: .regularExpression) != nil {
            return target
        }
        return nil
    }

    /// 画图意图（强制执行优先）："画海边""来画海边吧""画一张猫""帮我画日落，椰子树"
    static func extractImagePrompt(_ text: String) -> String? {
        // 明确拒绝时不再强制出图
        if text.range(of: "别画|不要画|不用画|不想画|别生成|不要生成") != nil { return nil }
        // 能力询问类（"你能画图吗"）：直接给一张通用示例图，体现强制执行
        if text.range(of: "能画|会画|可以画|画图吗|能生成图|会生成图") != nil {
            return "一张简洁可爱的插画，色彩柔和"
        }
        guard text.range(of: "画|绘|生成.{0,8}图|来.{0,6}张", options: .regularExpression) != nil else { return nil }
        var prompt = text
        for p in [
            "帮我画一张", "帮我画一幅", "帮我画个", "帮我画", "给我画一张", "给我画", "帮我生成一张", "帮我生成",
            "画一张", "画一幅", "画个", "画一下", "咱们来画", "我们来画", "一起来画", "来画", "画张", "画一幅",
            "生成一张", "生成一幅", "生成个", "帮我来一张", "来一张", "来一幅", "请画", "给我", "咱们", "我们",
            "一起", "试试", "生成", "画", "绘"
        ] {
            prompt = prompt.replacingOccurrences(of: p, with: "")
        }
        // 去尾部语气词与标点
        let fillers = Set("吧呀哦嘛呢吗了呗啊哈")
        while let last = prompt.last, fillers.contains(last) || last == " " {
            prompt.removeLast()
        }
        prompt = prompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !prompt.isEmpty else { return nil }
        return String(prompt.prefix(80))
    }

    /// 执行全部检测到的动作，返回可注入上下文的真实数据
    static func prefetchAll(for text: String, screenEnabled: Bool = false, screenUnlocked: Bool = false) async -> [PrefetchedData] {
        let actions = detect(text)
        guard !actions.isEmpty else { return [] }
        var out: [PrefetchedData] = []
        for action in actions {
            switch action {
            case .weather(let city):
                out.append(PrefetchedData(toolName: "get_weather", result: await WeatherService.getWeather(city: city)))
            case .news:
                out.append(PrefetchedData(toolName: "get_news", result: await NewsService.getNews(topic: nil)))
            case .musicPlay(let title, let artist):
                out.append(PrefetchedData(toolName: "play_music", result: await MusicService.play(title: title, artist: artist)))
            case .musicStop:
                out.append(PrefetchedData(toolName: "stop_music", result: await MusicService.stop()))
            case .time:
                out.append(PrefetchedData(toolName: "get_current_time", result: TimeService.now()))
            case .calculate(let expr):
                out.append(PrefetchedData(toolName: "calculate", result: CalculatorService.calculate(expr)))
            case .random(let lo, let hi, let label):
                out.append(PrefetchedData(toolName: "random_number", result: RandomService.random(min: lo, max: hi, label: label)))
            case .search(let q):
                out.append(PrefetchedData(toolName: "web_search", result: await WebSearchService.search(q)))
            case .reminder(let minutes, let note):
                out.append(PrefetchedData(toolName: "set_reminder", result: await ReminderService.schedule(minutes: minutes, text: note)))
            case .generateImage(let prompt):
                let (data, result) = await ImageGenService.generate(prompt: prompt)
                var name: String?
                if let data { name = ImageStore.save(data) }
                out.append(PrefetchedData(toolName: "generate_image", result: result, imageName: name))
            case .screen(let mode):
                if screenEnabled && screenUnlocked {
                    let (data, result) = await ScreenService.capture(mode: mode)
                    var name: String?
                    if let data { name = ImageStore.save(data) }
                    out.append(PrefetchedData(toolName: "read_screen", result: result, imageName: name))
                } else {
                    let why = screenEnabled ? "屏幕读取未解锁（需要密码），请引导用户到 设置→通用→屏幕读取 输入密码解锁" : "屏幕读取未开启，请引导用户到 设置→通用→屏幕读取 开启并设置密码"
                    out.append(PrefetchedData(toolName: "read_screen", result: "{\"status\":\"denied\",\"detail\":\"\(why)\"}", imageName: nil))
                }
            case .openURL(let target):
                out.append(PrefetchedData(toolName: "open_url", result: await OpenURLService.open(target), imageName: nil))
            case .clipboard:
                out.append(PrefetchedData(toolName: "read_clipboard", result: await ClipboardService.read(), imageName: nil))
            case .systemInfo:
                out.append(PrefetchedData(toolName: "system_info", result: SystemInfoService.info(), imageName: nil))
            case .call(let target):
                out.append(PrefetchedData(toolName: "make_call", result: await CallService.call(target: target), imageName: nil))
            }
        }
        return out
    }

    // MARK: - 提取器

    private static func extractMatches(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
            }
    }

    private static let cityStopWords: Set<String> = [
        "今天", "明天", "后天", "现在", "这里", "那边", "上午", "下午", "晚上", "周末",
        "本周", "下周", "一下", "帮我", "麻烦", "请问", "看看", "下个", "室外", "外面"
    ]

    static func extractCity(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "([\\p{Han}]{2,6}?)(?:的)?(?:天气|气温)") else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        var city = ns.substring(with: m.range(at: 1))
        if cityStopWords.contains(city) || city.count < 2 { return nil }
        for p in ["查", "看", "下", "的", "问"] {
            while city.hasPrefix(p) { city.removeFirst() }
        }
        return city.isEmpty ? nil : city
    }

    /// 提取数学表达式：消息中含运算意图时，抓取数字+运算符片段
    static func extractMathExpression(_ text: String) -> String? {
        guard text.range(of: "计算|算一下|等于多少|等于几|帮我算|加减乘除|\\d+\\s*[+\\-×÷*/]", options: .regularExpression) != nil else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "[0-9(][0-9+\\-*/().%\\s×÷^]{1,60}[0-9)]") else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var expr = ns.substring(with: m.range)
        expr = expr.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "^")
            .trimmingCharacters(in: .whitespaces)
        // 至少要有一个运算符
        guard expr.contains("+") || expr.contains("-") || expr.contains("*") || expr.contains("/") else { return nil }
        return expr
    }

    private static func extractNumberRange(_ text: String) -> (Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*(?:到|至|-|~)\\s*(\\d+)") else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 2 else { return nil }
        guard let lo = Int(ns.substring(with: m.range(at: 1))), let hi = Int(ns.substring(with: m.range(at: 2))), lo < hi else { return nil }
        return (lo, hi)
    }

    private static func extractSearchQuery(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?:搜索|搜一下|百度一下|谷歌一下|帮我搜)(?:一下)?[:：,，]?\\s*(.+)$") else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        let q = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return nil }
        return String(q.prefix(40))
    }

    private static func extractReminder(_ text: String) -> (Double, String)? {
        guard text.contains("提醒我") else { return nil }
        // 时长："3分钟/30秒/2小时" 之后
        guard let regex = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s*(分钟|分|小时|秒)") else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 2 else { return nil }
        guard let value = Double(ns.substring(with: m.range(at: 1))) else { return nil }
        let unit = ns.substring(with: m.range(at: 2))
        let minutes: Double
        switch unit {
        case "小时": minutes = value * 60
        case "秒": minutes = value / 60
        default: minutes = value
        }
        // 提醒内容：提醒我 之后、句末之前的部分
        var note = text
        if let r = text.range(of: "提醒我") {
            note = String(text[r.upperBound...])
        }
        note = note.replacingOccurrences(of: "\(ns.substring(with: m.range))", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !note.isEmpty else { return nil }
        return (max(0.1, minutes), String(note.prefix(50)))
    }
}

// MARK: - 计算器（NSExpression，白名单清洗）

enum CalculatorService {
    struct Result: Codable {
        var expression: String
        var value: String
        var ok: Bool
    }

    static func calculate(_ raw: String) -> String {
        // 白名单清洗：仅保留数字与安全运算符
        let allowed = Set("0123456789+-*/().% ")
        let cleaned = raw.filter { allowed.contains($0) }
        guard !cleaned.isEmpty else {
            return encode(Result(expression: raw, value: "", ok: false))
        }
        // percent 归一化（NSExpression 不支持 % 后缀）
        let expr = cleaned.replacingOccurrences(of: "%", with: "/100.0")
        let e = NSExpression(format: expr)
        guard let value = e.expressionValue(with: nil, context: nil) else {
            return encode(Result(expression: expr, value: "", ok: false))
        }
        let str: String
        if let d = value as? Double {
            str = d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.6g", d)
        } else {
            str = "\(value)"
        }
        return encode(Result(expression: expr, value: str, ok: true))
    }

    private static func encode(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false}"
    }
}

// MARK: - 随机数

enum RandomService {
    struct Result: Codable {
        var label: String
        var min: Int
        var max: Int
        var value: Int
        var display: String
    }

    static func random(min lo: Int, max hi: Int, label: String) -> String {
        let v = Int.random(in: lo...max(hi, lo))
        var display = "\(v)"
        if label.contains("硬币") {
            display = v == 1 ? "正面" : "反面"
        } else if label.contains("骰子") {
            display = "点数 \(v)"
        }
        return (try? JSONEncoder().encode(Result(label: label, min: lo, max: hi, value: v, display: display)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"value\":\(v)}"
    }
}

// MARK: - 网页搜索（Bing Web Search RSS）

struct WebSearchArgs: Codable {
    var query: String
}

enum WebSearchService {
    struct Result: Codable {
        struct Item: Codable {
            var title: String
            var snippet: String
            var url: String
        }
        var query: String
        var items: [Item]
    }

    static func search(_ query: String) async -> String {
        var c = URLComponents(string: "https://www.bing.com/search")!
        c.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "rss"),
            .init(name: "setmkt", value: "zh-CN"),
            .init(name: "count", value: "8")
        ]
        guard let url = c.url else { return "{\"error\":\"无效查询\"}" }
        do {
            try HostGuard.validate(url)
            let (data, resp) = try await APIClient.session.data(for: URLRequest(url: url))
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return "{\"error\":\"搜索服务暂时不可用\"}"
            }
            let parser = NewsService.RSSParser()
            let xml = XMLParser(data: data)
            xml.delegate = parser
            guard xml.parse(), !parser.items.isEmpty else {
                return "{\"query\":\"\(query)\",\"items\":[]}"
            }
            struct WebResult: Codable { var query: String; var items: [Result.Item] }
            let items = parser.items.prefix(6).map { item in
                Result.Item(
                    title: item.title,
                    snippet: String(item.description.prefix(120)),
                    url: item.source
                )
            }
            let payload = WebResult(query: query, items: Array(items))
            return String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        } catch {
            return "{\"error\":\"\(error.localizedDescription)\"}"
        }
    }
}

// MARK: - 定时提醒（本地通知）

struct ReminderArgs: Codable {
    var minutes: Double
    var text: String
}

enum ReminderService {
    struct Result: Codable {
        var status: String
        var minutes: Double
        var text: String
        var detail: String?
    }

    static func schedule(minutes: Double, text: String) async -> String {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard authorized else {
            return json(Result(status: "denied", minutes: minutes, text: text, detail: "系统通知权限未授权，请在系统设置中允许通知"))
        }
        let content = UNMutableNotificationContent()
        content.title = "角色提醒"
        content.body = text
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, minutes * 60), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            return json(Result(status: "error", minutes: minutes, text: text, detail: error.localizedDescription))
        }
        let detail = minutes < 1 ? String(format: "%.0f 秒后", minutes * 60) : String(format: "%.0f 分钟后", minutes)
        return json(Result(status: "scheduled", minutes: minutes, text: text, detail: detail))
    }

    private static func json(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"error\"}"
    }
}
