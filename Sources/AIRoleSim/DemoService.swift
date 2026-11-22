import Foundation

/// 演示模式：无 API Key 时本地模拟对话流。
/// 天气/新闻/音乐/时间等工具调用的是真实服务（无需 Key）；
/// 演示服务负责识别用户意图、发起对应的工具调用，并在拿到工具结果后组织口语化收尾。
struct DemoService {

    static func listModels() -> [String] {
        ["demo-chat", "demo-chat-pro"]
    }

    static func streamChat(
        characterName: String,
        messages: [ChatRequestMessage],
        exchangeIndex: Int
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lastTool = messages.last(where: { $0.role == "tool" })
                    let lastUser = messages.last(where: { $0.role == "user" })?.content ?? ""

                    var text: String
                    var calls: [CompletedToolCall] = []

                    if let tool = lastTool {
                        // 第二轮：基于真实工具结果组织口语化回复
                        text = Self.replyForToolResult(tool.content ?? "", characterName: characterName)
                    } else {
                        // 第一轮：意图检测统一走 IntentEngine，发起对应工具调用
                        let actions = IntentEngine.detect(lastUser)
                        var wantsMusicWithoutTitle = false
                        for action in actions {
                            switch action {
                            case .weather(let city):
                                calls.append(try Self.toolCall(name: "get_weather", args: WeatherArgs(city: city)))
                            case .news:
                                calls.append(try Self.toolCall(name: "get_news", args: NewsArgs(topic: nil)))
                            case .musicPlay(let title, let artist):
                                calls.append(try Self.toolCall(name: "play_music", args: MusicToolArgs(title: title, artist: artist)))
                            case .musicStop:
                                calls.append(try Self.toolCall(name: "stop_music", args: EmptyArgs()))
                            case .time:
                                calls.append(try Self.toolCall(name: "get_current_time", args: EmptyArgs()))
                            case .calculate(let expr):
                                calls.append(try Self.toolCall(name: "calculate", args: DemoCalcArgs(expression: expr)))
                            case .random(let lo, let hi, let label):
                                calls.append(try Self.toolCall(name: "random_number", args: DemoRandArgs(min: lo, max: hi, label: label)))
                            case .search(let q):
                                calls.append(try Self.toolCall(name: "web_search", args: WebSearchArgs(query: q)))
                            case .reminder(let m, let t):
                                calls.append(try Self.toolCall(name: "set_reminder", args: ReminderArgs(minutes: m, text: t)))
                            case .generateImage(let prompt):
                                calls.append(try Self.toolCall(name: "generate_image", args: ImageGenArgs(prompt: prompt)))
                            case .screen(let mode):
                                calls.append(try Self.toolCall(name: "read_screen", args: ScreenArgs(mode: mode)))
                            case .openURL(let target):
                                calls.append(try Self.toolCall(name: "open_url", args: OpenURLArgs(url: target)))
                            case .clipboard:
                                calls.append(try Self.toolCall(name: "read_clipboard", args: EmptyArgs()))
                            case .systemInfo:
                                calls.append(try Self.toolCall(name: "system_info", args: EmptyArgs()))
                            case .call(let target):
                                calls.append(try Self.toolCall(name: "make_call", args: CallArgs(target: target)))
                            }
                        }
                        if lastUser.range(of: "歌|音乐|曲", options: .regularExpression) != nil && calls.isEmpty {
                            wantsMusicWithoutTitle = true
                        }
                        if calls.isEmpty {
                            if wantsMusicWithoutTitle {
                                text = "想听什么歌？告诉我歌名，或者用书名号标出来，我马上放给你。"
                            } else {
                                text = Self.reply(characterName: characterName, userText: lastUser)
                                let memorable = exchangeIndex % 2 == 1 && lastUser.count >= 6
                                if memorable {
                                    let content = "用户提到：" + String(lastUser.prefix(24))
                                    calls = [try Self.toolCall(name: "save_memory", args: MemoryToolArgs(content: content, category: "事件", importance: 3, pinned: false))]
                                }
                            }
                        } else {
                            text = ""
                        }
                    }

                    // 模拟逐字流式输出
                    var buffer = ""
                    for (i, ch) in text.enumerated() {
                        try Task.checkCancellation()
                        buffer.append(ch)
                        if buffer.count >= 3 || i == text.count - 1 {
                            continuation.yield(.delta(buffer))
                            buffer = ""
                            try await Task.sleep(nanoseconds: 16_000_000)
                        }
                    }

                    if calls.isEmpty {
                        continuation.yield(.finished(reason: "stop", totalTokens: nil))
                    } else {
                        continuation.yield(.toolCalls(calls))
                        continuation.yield(.finished(reason: "tool_calls", totalTokens: nil))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct EmptyArgs: Codable {}
    struct DemoCalcArgs: Codable { var expression: String }
    struct DemoRandArgs: Codable { var min: Int; var max: Int; var label: String }

    // MARK: - 意图识别

    // MARK: - 工具调用构造

    private static func toolCall(name: String, args: some Codable) throws -> CompletedToolCall {
        let data = try JSONEncoder().encode(args)
        return CompletedToolCall(id: "demo-call-\(name)", name: name, arguments: String(decoding: data, as: UTF8.self))
    }

    // MARK: - 基于工具结果组织口语化回复

    private static func replyForToolResult(_ toolJSON: String, characterName: String) -> String {
        guard let data = toolJSON.data(using: .utf8) else {
            return "嗯，这件事我已经记下了。接下来想聊点什么？"
        }

        // 天气
        if let w = try? JSONDecoder().decode(WeatherService.Result.self, from: data) {
            var s = "刚帮你看了\(w.city)的天气——现在\(tempStr(w.temp_c))，\(w.desc)"
            if let f = w.feels_like_c { s += "，体感\(String(format: "%.0f", f))度" }
            s += "。"
            if let today = w.days.first {
                s += "今天最高\(String(format: "%.0f", today.hi))度、最低\(String(format: "%.0f", today.lo))度"
                if today.desc != w.desc { s += "，\(today.desc)" }
                s += "。"
            }
            if w.desc.contains("雨") {
                s += "出门记得带伞。"
            } else if let t = w.temp_c, t < 8 {
                s += "挺冷的，多穿点。"
            }
            s += "还想了解别的吗？"
            return s
        }

        // 新闻
        struct NewsItems: Codable {
            struct Item: Codable { var title: String; var source: String?; var time: String? }
            var items: [Item]?
        }
        if let n = try? JSONDecoder().decode(NewsItems.self, from: data), let items = n.items, !items.isEmpty {
            var s = "我看了下最近的新闻："
            let ordinals = Array("一二三")
            for (i, it) in items.prefix(3).enumerated() {
                s += "第\(ordinals[i])，\(it.title)"
                if let src = it.source, !src.isEmpty { s += "（\(src)）" }
                s += "；"
            }
            s += "想深入聊哪一条？"
            return s
        }

        // 音乐
        struct MusicStatus: Codable {
            var status: String
            var track: String?
            var artist: String?
        }
        if let m = try? JSONDecoder().decode(MusicStatus.self, from: data) {
            switch m.status {
            case "playing":
                var s = "已经为你播放"
                if let t = m.track { s += "《\(t)》" }
                if let a = m.artist, !a.isEmpty { s += "，\(a)的版本" }
                s += "了，好好听。想换别的随时说。"
                return s
            case "not_found":
                return "音乐库里没找到这首歌，换个歌名或者歌手试试？"
            default:
                return "音乐播放好像出了点问题，稍后再试一次？"
            }
        }

        // 时间
        struct TimeResult: Codable { var now: String?; var weekday: String? }
        if let t = try? JSONDecoder().decode(TimeResult.self, from: data) {
            var s = "现在是\(t.now ?? "--")"
            if let w = t.weekday { s += "，\(w)" }
            s += "。"
            return s
        }

        return "嗯，都办好了。接下来想聊点什么？"
    }

    private static func tempStr(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.0f", v) + "度"
    }

    // MARK: - 普通回复

    private static func reply(characterName: String, userText: String) -> String {
        let t = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(t.prefix(26))
        let pool = [
            "我先想了想你说的话——\"\(tail)\"。站在我的角度，这里面最关键的是你真正在意什么。我们可以顺着这个聊下去。",
            "关于\"\(tail)\"，我的第一反应是：别急着下结论，先把感受说完整。你刚才说这些的时候，语气里其实带着犹豫。",
            "有意思，\"\(tail)\"……如果换作是我，我会先弄清楚自己到底想从这里得到什么。你觉得呢？",
            "你说的这些我记下了。\(characterName)的直觉告诉我，比起计划本身，更值得讨论的是你为什么现在才开始想这件事。",
            "（认真听完，点了点头）\"\(tail)\"——如果你愿意，可以再往前多说一点：这件事里，最让你在意的是哪个部分？",
            "嗯……\"\(tail)\"。我倒想先反问你一句：如果这件事明天就解决了，你会先做什么？"
        ]
        return pool[abs(t.count) % pool.count]
    }
}
