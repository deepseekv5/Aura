import Foundation
import SwiftUI

// MARK: - 提示词构建

@MainActor
enum PromptBuilder {

    static func memoryBlock(store: AppStore, character: RoleProfile, lastUserText: String, topK: Int) -> String {
        MemoryEngine.contextBlock(
            entries: store.memories,
            characterID: character.id,
            query: lastUserText.isEmpty ? character.displayName : lastUserText,
            topK: topK
        )
    }

    static func systemPrompt(
        store: AppStore,
        character: RoleProfile,
        isGroup: Bool,
        memberNames: [String],
        lastUserText: String
    ) -> String {
        let settings = store.settings
        var lines: [String] = []

        lines.append("你将进行角色扮演，始终以「\(character.displayName)」的身份与用户交流，不要跳出角色。")
        lines.append("【人设】\(character.persona.isEmpty ? "性格一致、自然真诚，由你在对话中逐步呈现。" : character.persona)")
        if !character.scenario.isEmpty {
            lines.append("【场景】\(character.scenario)")
        }
        let userName = settings.userName.isEmpty ? "一位用户" : settings.userName
        lines.append("【用户】\(userName)\(settings.userBio.isEmpty ? "" : "。简介：\(settings.userBio)")")
        lines.append(
            "【你的长期记忆】\n以下是你从过往交流中记住的信息，格式为 [分类·重要度] 内容：\n"
            + memoryBlock(store: store, character: character, lastUserText: lastUserText, topK: settings.memoryTopK)
        )
        if character.memoryEnabled {
            lines.append(
                "【记忆工具】\n- save_memory：当了解到值得长期记住的新信息（事实、偏好、约定、重要事件）时主动保存；不要重复保存已有内容。\n- search_memory：需要回忆某件具体事情时检索记忆。"
            )
        }
        lines.append(
            "【真实世界能力（工具）】\n- get_weather(city)：查某城市实时天气与三天预报；用户提到天气、出门、穿衣时必须查询，不要编造。\n- get_news(topic)：查新闻资讯，可指定话题；聊到时事、热点时查询。\n- web_search(query)：联网搜索，不确定的事实、词条、背景资料都应搜索。\n- calculate(expression)：精确数学计算，涉及运算时必须使用，不要心算。\n- random_number(min, max, label)：随机数、掷骰子、抛硬币、抽签。\n- play_music(title, artist) / stop_music()：用本机音乐 App 播放/停止歌曲。\n- get_current_time()：查当前日期时间星期，涉及时间时查询。\n- set_reminder(minutes, text)：设定本地通知提醒，用户说『X分钟后提醒我…』时使用。\n- generate_image(prompt)：生成图片并展示给用户，用户想看图、画图、生成海报头像时使用。\n- read_screen(mode)：截取并查看用户屏幕（需要用户开启）。\n- open_url(url)：在浏览器打开网址。\n- read_clipboard()：读取剪贴板文字或图片。\n- system_info()：查电脑系统状态、电量、内存、磁盘。\n拿到结果后用自然口语转述，融入角色语气，不要罗列原始数据。"
        )
        lines.append(
            "【工具执行铁律】\n- 用户请求以上任何能力时，必须立刻调用对应工具执行，禁止只说『我可以……』而不执行，禁止用『你想要什么样的？』这类问题拖延——用户说画什么就画什么（如「来画海边吧」→ 立即 generate_image(prompt=\"海边\")），画完再说话。\n- 唯一例外：放歌但完全不知道歌名时，可以追问一次歌名；查天气但完全不知道城市名时，可以追问一次城市。\n- 除此之外一律先执行、后说话；执行结果用一两句话自然收尾，贴合角色语气。"
        )
        if isGroup {
            let others = memberNames.filter { $0 != character.displayName }.joined(separator: "、")
            lines.append(
                "【多人对话】这是群聊场景，参与者包括：\(others)。你只扮演「\(character.displayName)」。每条消息以「名字」开头标明发言者。请回应与你相关的发言，不要替其他角色发言。"
            )
        }
        lines.append(
            "【要求】\n- 以\(character.displayName)的语气自然回应，贴合人设，口语化，像真人一样有来有回，可以适当反问、追问，推动互动。\n- 可以偶尔用括号描写动作与神态（如「（笑了笑）」），让角色更生动，但不要频繁使用。\n- 上下文里以「名字」开头的消息来自其他发言者。\n- 回复简洁自然，不要长篇大论，不要罗列条目。"
        )
        if character.noEmojiReplies && settings.noEmojiReplies {
            lines.append("- 不要使用任何 emoji 表情符号。")
        }
        return lines.joined(separator: "\n\n")
    }

    /// 全量历史（不设上限）；assistant 历史清理思考残留；带图消息转为多模态内容（仅最近 8 条带图消息注入图片）
    static func historyMessages(conversation: Conversation, store: AppStore) -> [ChatRequestMessage] {
        let cleaned = conversation.messages.compactMap { m -> ChatMessage? in
            guard !(m.content.isEmpty && m.imagePaths.isEmpty) else { return nil }
            if m.role == .assistant, !m.content.isEmpty {
                var c = stripTextToolCalls(stripThinking(m.content)).trimmingCharacters(in: .whitespacesAndNewlines)
                if c.isEmpty { c = "（已执行操作）" }
                var copy = m
                copy.content = c
                return copy
            }
            return m
        }
        let imageMessageIDs = Set(cleaned.filter { !$0.imagePaths.isEmpty }.suffix(8).map { $0.id })

        return cleaned.map { m -> ChatRequestMessage in
            switch m.role {
            case .user:
                if imageMessageIDs.contains(m.id) {
                    var parts: [ContentPart] = []
                    if !m.content.isEmpty { parts.append(.text(m.content)) }
                    for path in m.imagePaths {
                        if let data = try? Data(contentsOf: store.imageURL(named: path)) {
                            parts.append(.imageData(base64: data.base64EncodedString()))
                        }
                    }
                    if !parts.isEmpty { return .user(parts: parts) }
                }
                return .user(m.content)
            case .assistant:
                if conversation.isGroup, let sp = m.speakerID, let name = store.character(id: sp)?.displayName {
                    return .assistant("「\(name)」\(m.content)")
                }
                return .assistant(m.content)
            }
        }
    }

    static func summarizePrompt(characterName: String, transcript: String) -> String {
        """
        以下是角色「\(characterName)」与用户的最近对话记录：

        \(transcript)

        请从中提炼值得长期记住的信息（事实、偏好、关系、约定、重要事件等），输出 JSON 数组，最多 8 条：
        [{"content":"一句话记忆","category":"事实|偏好|事件|关系|约定|情绪|其他","importance":1到5的整数,"pinned":布尔}]
        只输出 JSON 数组本身，不要任何解释。
        """
    }

    /// 移除回复中的 emoji（含变体选择符与 ZWJ 残留）
    static func stripEmoji(_ text: String) -> String {
        func banned(_ v: UInt32) -> Bool {
            switch v {
            case 0x1F000...0x1FAFF: return true
            case 0x2600...0x27BF: return true
            case 0x2B00...0x2BFF: return true
            case 0x1F1E6...0x1F1FF: return true
            case 0xFE00...0xFE0F: return true
            case 0x200D: return true
            default: return false
            }
        }
        let kept = text.unicodeScalars.filter { !banned($0.value) }
        return String(String.UnicodeScalarView(kept))
    }

    /// 过滤推理模型的思考标签：<think>…</think>、<reasoning>…</reasoning>；
    /// 未闭合时（思考进行中）隐藏从开标签到结尾的全部内容
    static func stripThinking(_ text: String) -> String {
        var result = text
        let ns: (String) -> NSRange = { NSRange($0.startIndex..., in: $0) }
        if let closed = try? NSRegularExpression(pattern: "<(?:think|reasoning|thought)[^>]*>[\\s\\S]*?</(?:think|reasoning|thought)[^>]*>") {
            result = closed.stringByReplacingMatches(in: result, range: ns(result), withTemplate: "")
        }
        if let open = try? NSRegularExpression(pattern: "<(?:think|reasoning|thought)[^>]*>[\\s\\S]*$") {
            result = open.stringByReplacingMatches(in: result, range: ns(result), withTemplate: "")
        }
        if let orphan = try? NSRegularExpression(pattern: "</(?:think|reasoning|thought)[^>]*>") {
            result = orphan.stringByReplacingMatches(in: result, range: ns(result), withTemplate: "")
        }
        return result
    }

    /// 流式显示时剥离文本型工具调用块（未闭合的也隐藏）
    static func stripTextToolCalls(_ text: String) -> String {
        var result = text
        let ns: (String) -> NSRange = { NSRange($0.startIndex..., in: $0) }
        if let closed = try? NSRegularExpression(pattern: "<tool_call>[\\s\\S]*?</tool_call>") {
            result = closed.stringByReplacingMatches(in: result, range: ns(result), withTemplate: "")
        }
        if let open = try? NSRegularExpression(pattern: "<tool_call>[\\s\\S]*$") {
            result = open.stringByReplacingMatches(in: result, range: ns(result), withTemplate: "")
        }
        return result
    }

    /// 解析文本型工具调用（GLM 等模型会把工具调用以 <tool_call>{...}</tool_call> 内嵌在回复里）
    /// 支持 function_name/name + parameters/arguments 两种字段命名
    static func parseTextToolCalls(_ text: String) -> (calls: [CompletedToolCall], cleaned: String) {
        guard let blockRegex = try? NSRegularExpression(pattern: "<tool_call>\\s*([\\s\\S]*?)\\s*</tool_call>") else {
            return ([], text)
        }
        let nst = text as NSString
        var calls: [CompletedToolCall] = []
        for m in blockRegex.matches(in: text, range: NSRange(location: 0, length: nst.length)) {
            let jsonStr = nst.substring(with: m.range(at: 1))
            guard let data = jsonStr.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let name = (obj["function_name"] as? String) ?? (obj["name"] as? String) ?? ""
            guard !name.isEmpty else { continue }
            let argsObj = obj["parameters"] ?? obj["arguments"] ?? obj["input"]
            let argsStr: String
            if let s = argsObj as? String {
                argsStr = s
            } else if let d = try? JSONSerialization.data(withJSONObject: argsObj ?? [:]) {
                argsStr = String(decoding: d, as: UTF8.self)
            } else {
                argsStr = "{}"
            }
            calls.append(CompletedToolCall(id: "text_call_\(calls.count)", name: name, arguments: argsStr))
        }
        guard !calls.isEmpty else { return ([], text) }
        let cleaned = blockRegex
            .stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (calls, cleaned)
    }
}

// MARK: - 会话引擎

@MainActor
final class ChatSessionModel: ObservableObject {

    @Published var pendingText = ""
    @Published var isStreaming = false
    @Published var statusText: String?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    let store: AppStore
    let conversationID: UUID

    init(store: AppStore, conversationID: UUID) {
        self.store = store
        self.conversationID = conversationID
    }

    func cancel() {
        task?.cancel()
    }

    func send(_ rawText: String, images: [Data] = []) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !text.isEmpty || !images.isEmpty else { return }
        errorMessage = nil
        let paths = images.compactMap { store.saveImageData($0) }
        store.appendMessage(to: conversationID, ChatMessage(role: .user, content: text, imagePaths: paths))
        run()
    }

    func regenerate() {
        guard !isStreaming else { return }
        guard let convo = store.conversation(id: conversationID),
              let last = convo.messages.last, last.role == .assistant else { return }
        store.deleteMessage(conversationID: conversationID, messageID: last.id)
        errorMessage = nil
        run()
    }

    /// 编辑已发送消息并从该处重新生成
    func editAndResend(messageID: UUID, newContent: String) {
        guard !isStreaming,
              let convo = store.conversation(id: conversationID),
              let idx = convo.messages.firstIndex(where: { $0.id == messageID }) else { return }
        var c = convo
        c.messages[idx].content = newContent
        c.messages = Array(c.messages.prefix(idx + 1))
        store.replaceConversation(c)
        errorMessage = nil
        run()
    }

    private func run() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await self.execute()
        }
    }

    private func execute() async {
        guard let convo = store.conversation(id: conversationID) else { return }
        isStreaming = true
        pendingText = ""
        defer {
            isStreaming = false
            statusText = nil
            pendingText = ""
        }
        do {
            if convo.isGroup {
                for memberID in convo.groupMemberIDs {
                    if Task.isCancelled { break }
                    guard store.character(id: memberID) != nil else { continue }
                    try await respond(characterID: memberID)
                }
            } else {
                try await respond(characterID: convo.characterID)
            }
        } catch is CancellationError {
            // 中断：已生成的部分内容已在 respond 内落库
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func respond(characterID: UUID) async throws {
        guard let convo = store.conversation(id: conversationID),
              let character = store.character(id: characterID) else { return }

        pendingText = ""
        var fullText = ""
        var notes: [String] = []
        var generatedImageNames: [String] = []

        let settings = store.settings
        let profile = store.effectiveProfile(for: character)
        if !settings.demoMode && profile == nil {
            throw APIError.notConfigured
        }

        if convo.isGroup {
            statusText = "「\(character.displayName)」回应中…"
        } else {
            statusText = "思考中…"
        }

        let memberNames = convo.isGroup ? convo.groupMemberIDs.compactMap { store.character(id: $0)?.displayName } : []
        let lastUser = convo.messages.last(where: { $0.role == .user })?.content ?? ""

        // 基础上下文（system + 全量历史）
        var messages: [ChatRequestMessage] = [
            .system(PromptBuilder.systemPrompt(store: store, character: character, isGroup: convo.isGroup, memberNames: memberNames, lastUserText: lastUser))
        ]
        messages += PromptBuilder.historyMessages(conversation: convo, store: store)

        var tools = APIClient.memoryTools
        if !character.memoryEnabled {
            tools.removeAll { $0.function.name == "save_memory" || $0.function.name == "search_memory" }
        }

        // 意图兜底：命中意图时引擎自动获取真实数据并注入（不依赖模型）
        if !settings.demoMode {
            let prefetched = await IntentEngine.prefetchAll(
                for: lastUser,
                screenEnabled: settings.screenEnabled,
                screenUnlocked: settings.screenPasswordHash.isEmpty || store.screenUnlocked
            )
            if !prefetched.isEmpty {
                statusText = "已自动获取实时数据…"
                let block = prefetched.map { "[\($0.toolName)]\n\($0.result)" }.joined(separator: "\n\n")
                let text = "以下是你需要的实时数据（系统已自动获取，可信）：\n\(block)\n请直接基于以上真实数据，以角色口吻自然回答用户；不要为此再次调用相同工具，不要提及 JSON 或系统。"
                let imageParts = prefetched.compactMap { pf -> ContentPart? in
                    guard let name = pf.imageName,
                          let data = try? Data(contentsOf: store.imageURL(named: name)) else { return nil }
                    return .imageData(base64: data.base64EncodedString())
                }
                if imageParts.isEmpty {
                    messages.append(.system(text))
                } else {
                    messages.append(.system(parts: [ContentPart.text(text)] + imageParts))
                }
                generatedImageNames += prefetched.compactMap { $0.imageName }
            }
        }

        let exchangeIndex = convo.messages.filter { $0.role == .user }.count

        if settings.demoMode {
            // 演示模式：流式 + 模拟工具调用循环
            var iteration = 0
            while iteration < 4 {
                iteration += 1
                var iterText = ""
                var calls: [CompletedToolCall] = []
                let stream = DemoService.streamChat(characterName: character.displayName, messages: messages, exchangeIndex: exchangeIndex)
                do {
                    for try await event in stream {
                        switch event {
                        case .delta(let d):
                            iterText += d
                            pendingText = PromptBuilder.stripTextToolCalls(PromptBuilder.stripThinking(fullText + iterText))
                        case .toolCalls(let c):
                            calls = c
                        case .finished:
                            break
                        }
                    }
                } catch is CancellationError {}
                fullText += iterText
                if calls.isEmpty || Task.isCancelled { break }
                messages.append(.assistantToolCall(iterText.isEmpty ? nil : iterText, calls))
                for call in calls {
                    let result = await executeTool(call: call, character: character, notes: &notes, imageNames: &generatedImageNames)
                    messages.append(.toolResult(call.id, result))
                }
                statusText = notes.isEmpty ? "正在查询…" : "已记忆 \(notes.count) 条"
            }
        } else {
            // 真实模式：工具决策走非流式（实测最可靠），执行完再流式生成口语化回复
            guard let p = profile else { throw APIError.notConfigured }
            var decision = messages
            var decisionRound = 0
            while decisionRound < 4 {
                decisionRound += 1
                if Task.isCancelled { break }
                statusText = decisionRound == 1 ? "思考中…" : "正在执行工具…"
                let d = try await APIClient.completeOnce(
                    profile: p,
                    messages: decision,
                    tools: tools,
                    temperature: character.temperatureOverride
                )
                var calls = d.toolCalls
                var dtext = d.text ?? ""
                // 文本型工具调用兜底（GLM 等模型内嵌 <tool_call>）
                if calls.isEmpty {
                    let (parsed, cleaned) = PromptBuilder.parseTextToolCalls(dtext)
                    if !parsed.isEmpty {
                        calls = parsed
                        dtext = cleaned
                    }
                }
                if calls.isEmpty { break }
                decision.append(.assistantToolCall(dtext.isEmpty ? nil : dtext, calls))
                for call in calls {
                    let result = await executeTool(call: call, character: character, notes: &notes, imageNames: &generatedImageNames)
                    decision.append(.toolResult(call.id, result))
                    if call.name == "read_screen", let lastName = generatedImageNames.last,
                       let data = try? Data(contentsOf: store.imageURL(named: lastName)) {
                        decision.append(.user(parts: [
                            .text("（这是刚截取的屏幕图片，请基于它回答用户）"),
                            .imageData(base64: data.base64EncodedString())
                        ]))
                    }
                }
                statusText = notes.isEmpty ? "正在整理结果…" : "已记忆 \(notes.count) 条"
            }

            // 流式生成最终回复（不再带工具，模型只负责说话）
            decision.append(.system("所有工具已执行完毕，结果见上文。请直接基于结果，以「\(character.displayName)」的口吻生成最终回复；不要再尝试调用任何工具，不要输出 JSON 或工具标记。"))
            messages = decision
        }

        // 流式成文阶段
        var iterText2 = ""
        let finalStream: AsyncThrowingStream<ChatStreamEvent, Error>
        if settings.demoMode {
            finalStream = DemoService.streamChat(characterName: character.displayName, messages: messages, exchangeIndex: exchangeIndex)
        } else if let p = profile {
            finalStream = APIClient.streamChat(
                profile: p,
                messages: messages,
                tools: nil,
                temperatureOverride: character.temperatureOverride
            )
        } else {
            throw APIError.notConfigured
        }
        do {
            for try await event in finalStream {
                switch event {
                case .delta(let d):
                    iterText2 += d
                    pendingText = PromptBuilder.stripTextToolCalls(PromptBuilder.stripThinking(fullText + iterText2))
                case .toolCalls(let c):
                    // 生成阶段若仍出现工具调用（极少），直接执行
                    for call in c {
                        let result = await executeTool(call: call, character: character, notes: &notes, imageNames: &generatedImageNames)
                        fullText += "\n\(result)"
                    }
                case .finished:
                    break
                }
            }
        } catch is CancellationError {
            // 保留已生成部分
        }
        fullText += iterText2

        let finalText = PromptBuilder.stripEmoji(
            PromptBuilder.stripTextToolCalls(PromptBuilder.stripThinking(fullText.trimmingCharacters(in: .whitespacesAndNewlines)))
        )
        if !finalText.isEmpty || !notes.isEmpty || !generatedImageNames.isEmpty {
            let m = ChatMessage(
                role: .assistant,
                content: finalText.isEmpty ? "（默默把这些记了下来。）" : finalText,
                speakerID: character.id,
                memoryNotes: notes,
                modelUsed: settings.demoMode ? "演示模式" : profile?.model,
                imagePaths: generatedImageNames
            )
            store.appendMessage(to: conversationID, m)

            // 自动朗读（可设置关闭）
            if settings.ttsAuto, !finalText.isEmpty {
                Task { await AudioPlayerManager.shared.toggle(message: m, settings: settings) }
            }
        } else {
            throw APIError.decoding("模型没有返回内容")
        }
        pendingText = ""
    }

    private func executeTool(call: CompletedToolCall, character: RoleProfile, notes: inout [String], imageNames: inout [String]) async -> String {
        func decode<T: Codable>(_ type: T.Type) -> T? {
            guard let data = call.arguments.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        func errJSON(_ msg: String) -> String {
            "{\"error\":\"\(msg.replacingOccurrences(of: "\"", with: "'"))\"}"
        }

        switch call.name {
        case "generate_image":
            guard let args = decode(ImageGenArgs.self), !args.prompt.isEmpty else { return errJSON("参数无法解析") }
            statusText = "正在生成图片…"
            let (data, result) = await ImageGenService.generate(
                prompt: args.prompt,
                width: args.width ?? 768,
                height: args.height ?? 768
            )
            if let data, let name = store.saveImageData(data) {
                imageNames.append(name)
            }
            return result

        case "web_search":
            guard let args = decode(WebSearchArgs.self) else { return errJSON("参数无法解析") }
            statusText = "正在搜索…"
            return await WebSearchService.search(args.query)

        case "calculate":
            struct CalcArgs: Codable { var expression: String }
            guard let args = decode(CalcArgs.self) else { return errJSON("参数无法解析") }
            statusText = "正在计算…"
            return CalculatorService.calculate(args.expression)

        case "random_number":
            struct RandArgs: Codable { var min: Int?; var max: Int?; var label: String? }
            let args = decode(RandArgs.self)
            statusText = "正在抽取…"
            return RandomService.random(min: args?.min ?? 1, max: args?.max ?? 100, label: args?.label ?? "随机数")

        case "set_reminder":
            guard let args = decode(ReminderArgs.self) else { return errJSON("参数无法解析") }
            statusText = "正在设定提醒…"
            return await ReminderService.schedule(minutes: max(0.1, args.minutes), text: args.text)

        case "read_screen":
            let args = decode(ScreenArgs.self)
            guard store.settings.screenEnabled else {
                return "{\"status\":\"denied\",\"detail\":\"屏幕读取未开启，请引导用户到 设置→通用→屏幕读取 开启并设置密码\"}"
            }
            guard store.settings.screenPasswordHash.isEmpty || store.screenUnlocked else {
                return "{\"status\":\"locked\",\"detail\":\"屏幕读取已锁定（需要密码），请引导用户到 设置→通用→屏幕读取 输入密码解锁\"}"
            }
            statusText = "正在截取屏幕…"
            let (data, result) = await ScreenService.capture(mode: args?.mode ?? store.settings.screenMode)
            if let data, let name = store.saveImageData(data) {
                imageNames.append(name)
            }
            return result

        case "make_call":
            guard let args = decode(CallArgs.self) else { return errJSON("参数无法解析") }
            statusText = "正在发起通话…"
            return await CallService.call(target: args.target)

        case "open_url":
            guard let args = decode(OpenURLArgs.self) else { return errJSON("参数无法解析") }
            statusText = "正在打开网址…"
            return await OpenURLService.open(args.url)

        case "read_clipboard":
            statusText = "正在读剪贴板…"
            return await ClipboardService.read()

        case "system_info":
            statusText = "正在查看系统状态…"
            return SystemInfoService.info()

        case "save_memory":
            guard let args = decode(MemoryToolArgs.self),
                  !args.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return errJSON("参数无法解析")
            }
            let entry = store.addMemory(
                characterID: character.id,
                content: args.content,
                category: args.category ?? "其他",
                importance: args.importance ?? 3,
                pinned: args.pinned ?? false,
                source: "ai"
            )
            notes.append(args.content)
            statusText = "已记忆：\(String(args.content.prefix(14)))"
            return "{\"ok\":true,\"id\":\"\(entry.id.uuidString)\"}"

        case "search_memory":
            guard let args = decode(SearchToolArgs.self) else { return "{\"results\":[]}" }
            let hits = MemoryEngine.relevant(from: store.memories, characterID: character.id, query: args.query, limit: 6)
            store.recordMemoryUse(ids: hits.map { $0.id })
            statusText = "正在回忆…"
            struct Hit: Codable { let content: String; let category: String; let importance: Int }
            let payload = hits.map { Hit(content: $0.content, category: $0.category, importance: $0.importance) }
            if let jsonData = try? JSONEncoder().encode(payload),
               let json = String(data: jsonData, encoding: .utf8) {
                return "{\"results\":\(json)}"
            }
            return "{\"results\":[]}"

        case "get_weather":
            guard let args = decode(WeatherArgs.self) else { return errJSON("参数无法解析") }
            statusText = "正在查天气…"
            return await WeatherService.getWeather(city: args.city)

        case "get_news":
            let args = decode(NewsArgs.self)
            statusText = "正在看新闻…"
            return await NewsService.getNews(topic: args?.topic)

        case "play_music":
            guard let args = decode(MusicToolArgs.self) else { return errJSON("参数无法解析") }
            statusText = "正在播放音乐…"
            return await MusicService.play(title: args.title, artist: args.artist)

        case "stop_music":
            statusText = "正在停止音乐…"
            return await MusicService.stop()

        case "get_current_time":
            statusText = "正在看时间…"
            return TimeService.now()

        default:
            return errJSON("未知工具")
        }
    }
}
