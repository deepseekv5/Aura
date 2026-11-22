import Foundation

// MARK: - 内置服务地址安全校验
// 内置工具（天气/新闻）只允许访问受信任的公共 HTTPS 服务，
// 拒绝 localhost、环回、私有与保留地址。

enum HostGuard {
    static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw APIError.invalidURL(url.absoluteString)
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw APIError.invalidURL(url.absoluteString)
        }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            throw APIError.invalidURL("禁止访问本地地址")
        }
        var h = host
        if h.hasPrefix("["), h.hasSuffix("]") {
            h = String(h.dropFirst().dropLast())
        }
        if isForbiddenIPv4(h) || isForbiddenIPv6(h) {
            throw APIError.invalidURL("禁止访问私有或保留地址")
        }
    }

    private static func isForbiddenIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".").map(String.init)
        guard parts.count == 4 else { return false }
        let nums = parts.compactMap { Int($0) }
        guard nums.count == 4, nums.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return false }
        let a = nums[0], b = nums[1]
        if a == 0 || a == 10 || a == 127 { return true }
        if a == 169 && b == 254 { return true }          // 链路本地
        if a == 172 && (16...31).contains(b) { return true }
        if a == 192 && b == 168 { return true }
        if a == 100 && (64...127).contains(b) { return true }  // CGNAT
        if a == 198 && (b == 18 || b == 19) { return true }    // 基准测试
        if a == 192 && b == 0 { return true }             // IETF 协议分配
        if a == 203 && b == 0 && nums[2] == 113 { return true } // TEST-NET-3
        if a == 198 && b == 51 && nums[2] == 100 { return true } // TEST-NET-2
        if a >= 224 { return true }                       // 组播/保留
        return false
    }

    private static func isForbiddenIPv6(_ s: String) -> Bool {
        let l = s.lowercased()
        if l == "::" || l == "::1" { return true }
        if l.hasPrefix("fe80") || l.hasPrefix("fc") || l.hasPrefix("fd") || l.hasPrefix("ff") { return true }
        if l.contains("::ffff:") || l.hasPrefix("::") && !l.hasSuffix("::") { return true } // IPv4-mapped/兼容
        if l.hasPrefix("64:ff9b:") { return true } // NAT64
        return false
    }
}

// MARK: - 天气（Open-Meteo，免费无 Key）

struct WeatherArgs: Codable {
    var city: String
}

enum WeatherService {

    struct GeoResponse: Decodable {
        struct Item: Decodable {
            var latitude: Double
            var longitude: Double
            var name: String
            var country: String?
            var admin1: String?
        }
        var results: [Item]?
    }

    struct Forecast: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double?
            var apparent_temperature: Double?
            var relative_humidity_2m: Int?
            var weather_code: Int?
            var wind_speed_10m: Double?
        }
        struct Daily: Decodable {
            var time: [String]?
            var weather_code: [Int]?
            var temperature_2m_max: [Double]?
            var temperature_2m_min: [Double]?
        }
        var current: Current?
        var daily: Daily?
    }

    struct DayInfo: Codable {
        var date: String
        var hi: Double
        var lo: Double
        var desc: String
    }

    struct Result: Codable {
        var city: String
        var location: String
        var temp_c: Double?
        var feels_like_c: Double?
        var humidity: Int?
        var wind_kmh: Double?
        var desc: String
        var days: [DayInfo]
    }

    static func weatherDesc(_ code: Int?) -> String {
        guard let code else { return "未知" }
        switch code {
        case 0: return "晴"
        case 1: return "大致晴朗"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "有雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻雨"
        case 61: return "小雨"
        case 63: return "中雨"
        case 65: return "大雨"
        case 66, 67: return "冻雨"
        case 71: return "小雪"
        case 73: return "中雪"
        case 75: return "大雪"
        case 77: return "雪粒"
        case 80: return "阵雨"
        case 81: return "强阵雨"
        case 82: return "暴雨"
        case 85, 86: return "阵雪"
        case 95: return "雷阵雨"
        case 96, 99: return "雷阵雨伴冰雹"
        default: return "天气多变"
        }
    }

    static func getWeather(city: String) async -> String {
        let primary = await getWeatherOpenMeteo(city: city)
        // 失败（错误/找不到城市）时用 wttr.in 兜底
        if !primary.contains("\"error\"") { return primary }
        let fallback = await getWeatherWttr(city: city)
        return fallback.contains("\"error\"") ? primary : fallback
    }

    /// wttr.in 兜底（j1 JSON 格式）
    private static func getWeatherWttr(city: String) async -> String {
        struct WttrCurrent: Decodable {
            var temp_C: String?
            var FeelsLikeC: String?
            var humidity: String?
            var windspeedKmph: String?
            var weatherDesc: [WttrDesc]?
        }
        struct WttrDesc: Decodable { var value: String? }
        struct WttrDay: Decodable {
            var date: String?
            var mintempC: String?
            var maxtempC: String?
            var hourly: [WttrHour]?
        }
        struct WttrHour: Decodable { var weatherDesc: [WttrDesc]? }
        struct WttrResponse: Decodable {
            var current_condition: [WttrCurrent]?
            var weather: [WttrDay]?
        }
        struct WttrResult: Codable {
            var city: String
            var location: String
            var temp_c: Double?
            var feels_like_c: Double?
            var humidity: Int?
            var wind_kmh: Double?
            var desc: String
            var days: [WeatherService.DayInfo]
        }
        var c = URLComponents(string: "https://wttr.in/\(city.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? city)")!
        c.queryItems = [.init(name: "format", value: "j1")]
        guard let url = c.url else { return "{\"error\":\"无效城市\"}" }
        do {
            try HostGuard.validate(url)
            let (data, resp) = try await APIClient.dataWithRetry(URLRequest(url: url))
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return "{\"error\":\"天气服务不可用\"}"
            }
            let w = try JSONDecoder().decode(WttrResponse.self, from: data)
            guard let cur = w.current_condition?.first else { return "{\"error\":\"无天气数据\"}" }
            var days: [WeatherService.DayInfo] = []
            for (i, d) in (w.weather ?? []).prefix(3).enumerated() {
                days.append(WeatherService.DayInfo(
                    date: d.date ?? "",
                    hi: Double(d.maxtempC ?? "0") ?? 0,
                    lo: Double(d.mintempC ?? "0") ?? 0,
                    desc: d.hourly?.first?.weatherDesc?.first?.value ?? ""
                ))
            }
            let result = WttrResult(
                city: city,
                location: city,
                temp_c: Double(cur.temp_C ?? ""),
                feels_like_c: Double(cur.FeelsLikeC ?? ""),
                humidity: Int(cur.humidity ?? ""),
                wind_kmh: Double(cur.windspeedKmph ?? ""),
                desc: cur.weatherDesc?.first?.value ?? "",
                days: days
            )
            return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        } catch {
            return "{\"error\":\"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "'"))\"}"
        }
    }

    static func getWeatherOpenMeteo(city: String) async -> String {
        do {
            // 地理编码
            var g = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            g.queryItems = [
                .init(name: "name", value: city),
                .init(name: "count", value: "1"),
                .init(name: "language", value: "zh"),
                .init(name: "format", value: "json")
            ]
            let geoURL = g.url!
            try HostGuard.validate(geoURL)
            let (gd, gr) = try await APIClient.dataWithRetry(URLRequest(url: geoURL))
            if let http = gr as? HTTPURLResponse, http.statusCode >= 400 {
                return "{\"error\":\"地理编码失败(HTTP \(http.statusCode))\"}"
            }
            let geo = try JSONDecoder().decode(GeoResponse.self, from: gd)
            guard let loc = geo.results?.first else {
                return "{\"error\":\"找不到城市「\(city)」\"}"
            }

            // 天气预报
            var f = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            f.queryItems = [
                .init(name: "latitude", value: String(loc.latitude)),
                .init(name: "longitude", value: String(loc.longitude)),
                .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
                .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
                .init(name: "timezone", value: "auto"),
                .init(name: "forecast_days", value: "3")
            ]
            let fcURL = f.url!
            try HostGuard.validate(fcURL)
            let (fd, fr) = try await APIClient.dataWithRetry(URLRequest(url: fcURL))
            if let http = fr as? HTTPURLResponse, http.statusCode >= 400 {
                return "{\"error\":\"天气查询失败(HTTP \(http.statusCode))\"}"
            }
            let fc = try JSONDecoder().decode(Forecast.self, from: fd)

            var days: [DayInfo] = []
            if let t = fc.daily?.time {
                for (i, day) in t.enumerated() where i < 3 {
                    days.append(DayInfo(
                        date: day,
                        hi: fc.daily?.temperature_2m_max?[safe: i] ?? 0,
                        lo: fc.daily?.temperature_2m_min?[safe: i] ?? 0,
                        desc: weatherDesc(fc.daily?.weather_code?[safe: i])
                    ))
                }
            }
            let result = Result(
                city: city,
                location: [loc.admin1, loc.name, loc.country].compactMap { $0 }.joined(separator: "·"),
                temp_c: fc.current?.temperature_2m,
                feels_like_c: fc.current?.apparent_temperature,
                humidity: fc.current?.relative_humidity_2m,
                wind_kmh: fc.current?.wind_speed_10m,
                desc: weatherDesc(fc.current?.weather_code),
                days: days
            )
            let data = try JSONEncoder().encode(result)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "{\"error\":\"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "'"))\"}"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 新闻（Bing News RSS 为主，Google News RSS 兜底）

struct NewsArgs: Codable {
    var topic: String?
}

enum NewsService {

    final class RSSParser: NSObject, XMLParserDelegate {
        struct Item {
            var title = ""
            var source = ""
            var date = ""
            var description = ""
        }
        var items: [Item] = []

        private var inItem = false
        private var currentTag = ""
        private var currentText = ""
        private var currentItem: Item?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "item" {
                inItem = true
                currentItem = Item()
            }
            if inItem {
                currentTag = elementName
                currentText = ""
                if elementName == "source", let s = attributeDict["url"] {
                    currentItem?.source = s
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inItem { currentText += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "item" {
                if var it = currentItem, !it.title.isEmpty {
                    // Google News 的标题形如 "标题 - 来源"
                    if it.source.isEmpty, let r = it.title.range(of: " - ", options: .backwards) {
                        it.source = String(it.title[r.upperBound...])
                        it.title = String(it.title[..<r.lowerBound])
                    }
                    items.append(it)
                }
                currentItem = nil
                inItem = false
            } else if inItem {
                switch currentTag {
                case "title": currentItem?.title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                case "pubDate": currentItem?.date = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                case "source": currentItem?.source = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                case "description": currentItem?.description = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                default: break
                }
            }
            currentTag = ""
        }
    }

    static func getNews(topic: String?) async -> String {
        let q = (topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var result = await fetchFromBing(topic: q)
        if result.isEmpty {
            result = await fetchFromGoogle(topic: q)
        }
        if result.isEmpty {
            return "{\"error\":\"暂时没拿到新闻，稍后再试\"}"
        }
        return result
    }

    private static func fetchFromBing(topic: String) async -> String {
        let query = topic.isEmpty ? "今日重要新闻" : topic
        var c = URLComponents(string: "https://www.bing.com/news/search")!
        c.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "RSS"),
            .init(name: "setmkt", value: "zh-CN")
        ]
        return await fetchRSS(url: c.url!, topic: query, sourceName: "Bing")
    }

    private static func fetchFromGoogle(topic: String) async -> String {
        let query = topic.isEmpty ? "头条" : topic
        var c = URLComponents(string: "https://news.google.com/rss/search")!
        c.queryItems = [
            .init(name: "q", value: query),
            .init(name: "hl", value: "zh-CN"),
            .init(name: "gl", value: "CN"),
            .init(name: "ceid", value: "CN:zh-Hans")
        ]
        return await fetchRSS(url: c.url!, topic: query, sourceName: "Google News")
    }

    static func fetchRSS(url: URL, topic: String, sourceName: String) async -> String {
        do {
            try HostGuard.validate(url)
            let (data, resp) = try await APIClient.dataWithRetry(URLRequest(url: url))
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return "" }
            let parser = RSSParser()
            let xml = XMLParser(data: data)
            xml.delegate = parser
            guard xml.parse(), !parser.items.isEmpty else { return "" }

            struct NewsResult: Codable {
                struct Item: Codable {
                    var title: String
                    var source: String
                    var time: String
                }
                var topic: String
                var provider: String
                var items: [Item]
            }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            let formats = ["EEE, dd MMM yyyy HH:mm:ss ZZZZ", "dd MMM yyyy HH:mm:ss ZZZZ"]
            let list = parser.items.prefix(6).map { it -> NewsResult.Item in
                var time = ""
                for fmt in formats {
                    df.dateFormat = fmt
                    if let d = df.date(from: it.date) {
                        let zh = DateFormatter()
                        zh.locale = Locale(identifier: "zh_CN")
                        zh.dateFormat = "M月d日 HH:mm"
                        time = zh.string(from: d)
                        break
                    }
                }
                return NewsResult.Item(title: it.title, source: it.source, time: time)
            }
            let payload = NewsResult(topic: topic, provider: sourceName, items: Array(list))
            let out = try JSONEncoder().encode(payload)
            return String(decoding: out, as: UTF8.self)
        } catch {
            return ""
        }
    }
}

// MARK: - 音乐（本机音乐 App，AppleScript）

struct MusicToolArgs: Codable {
    var title: String
    var artist: String?
}

enum MusicService {

    struct Result: Codable {
        var status: String   // playing / not_found / stopped / error
        var track: String?
        var artist: String?
        var detail: String?
    }

    static func json(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"error\"}"
    }

    static func runOSA(_ script: String) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                } catch {
                    cont.resume(returning: "ERROR: \(error.localizedDescription)")
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: out.isEmpty ? "OK" : out)
            }
        }
    }

    static func play(title: String, artist: String?) async -> String {
        guard !title.isEmpty else { return json(Result(status: "error", detail: "歌曲名不能为空")) }
        let escTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        var cond = ""
        if let a = artist, !a.isEmpty {
            let escA = a.replacingOccurrences(of: "\"", with: "\\\"")
            cond = " and artist contains \"\(escA)\""
        }
        let script = """
        tell application "Music"
            set ms to (every track of library playlist 1 whose name contains "\(escTitle)"\(cond))
            if (count of ms) = 0 then return "NOT_FOUND"
            play item 1 of ms
            return (name of item 1 of ms) & "|" & (artist of item 1 of ms)
        end tell
        """
        let out = await runOSA(script)
        if out == "NOT_FOUND" {
            return json(Result(status: "not_found"))
        }
        if out.hasPrefix("ERROR") || out.contains("error") {
            return json(Result(status: "error", detail: out))
        }
        let parts = out.split(separator: "|").map(String.init)
        return json(Result(status: "playing", track: parts.first, artist: parts.count > 1 ? parts[1] : nil))
    }

    static func stop() async -> String {
        _ = await runOSA("tell application \"Music\" to stop")
        return json(Result(status: "stopped"))
    }
}

// MARK: - 当前时间

enum TimeService {
    static func now() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let wd = DateFormatter()
        wd.locale = Locale(identifier: "zh_CN")
        wd.dateFormat = "EEEE"
        let now = Date()
        return "{\"now\":\"\(df.string(from: now))\",\"weekday\":\"\(wd.string(from: now))\"}"
    }
}


// MARK: - 免费生图（Pollinations，无需 Key）

struct ImageGenArgs: Codable {
    var prompt: String
    var width: Int?
    var height: Int?
}

enum ImageGenService {
    struct Result: Codable {
        var status: String
        var prompt: String
        var detail: String?
    }

    static func json(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"error\"}"
    }

    /// 返回 (图片数据, 工具结果 JSON)
    static func generate(prompt: String, width: Int = 768, height: Int = 768) async -> (Data?, String) {
        var c = URLComponents(string: "https://image.pollinations.ai/prompt/\(prompt.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? prompt)")!
        c.queryItems = [
            .init(name: "width", value: String(min(1024, max(256, width)))),
            .init(name: "height", value: String(min(1024, max(256, height)))),
            .init(name: "nologo", value: "true"),
            .init(name: "seed", value: String(Int.random(in: 1...999_999)))
        ]
        guard let url = c.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "image.pollinations.ai" else {
            return (nil, json(Result(status: "error", prompt: prompt, detail: "生图地址无效")))
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 120
            let (data, resp) = try await APIClient.dataWithRetry(req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                return (nil, json(Result(status: "error", prompt: prompt, detail: "生图服务暂时不可用（HTTP \(code)，已重试），稍后再试")))
            }
            return (data, json(Result(status: "ok", prompt: prompt, detail: nil)))
        } catch {
            return (nil, json(Result(status: "error", prompt: prompt, detail: error.localizedDescription)))
        }
    }
}
