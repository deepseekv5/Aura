import Foundation

// MARK: - 错误

enum APIError: LocalizedError {
    case invalidURL(String)
    case http(Int, String)
    case decoding(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "API 地址无效：\(u)"
        case .http(let code, let body): return "请求失败（HTTP \(code)）：\(body)"
        case .decoding(let m): return "响应解析失败：\(m)"
        case .notConfigured: return "API 未配置：请在设置中填写 Base URL、API Key 与模型名（也可临时开启演示模式体验）"
        }
    }
}

// MARK: - 流事件

struct CompletedToolCall: Identifiable, Hashable {
    let id: String
    let name: String
    let arguments: String
}

enum ChatStreamEvent {
    case delta(String)
    case toolCalls([CompletedToolCall])
    case finished(reason: String?, totalTokens: Int?)
}

// MARK: - 请求消息

/// 多模态内容片段（文本 / 图片 base64）
struct ContentPart: Encodable {
    enum PartType: String, Encodable {
        case text
        case imageURL = "image_url"
    }
    struct ImageURL: Encodable {
        var url: String
    }

    var type: PartType
    var text: String?
    var image_url: ImageURL?

    static func text(_ t: String) -> ContentPart {
        ContentPart(type: .text, text: t, image_url: nil)
    }
    static func imageData(base64: String, mime: String = "image/jpeg") -> ContentPart {
        ContentPart(type: .imageURL, text: nil, image_url: ImageURL(url: "data:\(mime);base64,\(base64)"))
    }
}

struct ChatRequestMessage: Encodable {
    var role: String
    var content: String?
    /// 多模态内容（图片+文本）；非空时 content 以数组形式编码
    var contentParts: [ContentPart]?
    var tool_calls: [ToolCallPayload]?
    var tool_call_id: String?

    private enum CodingKeys: String, CodingKey {
        case role, content, tool_calls, tool_call_id
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        if let parts = contentParts, !parts.isEmpty {
            try c.encode(parts, forKey: .content)
        } else {
            try c.encodeIfPresent(content, forKey: .content)
        }
        try c.encodeIfPresent(tool_calls, forKey: .tool_calls)
        try c.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
    }

    static func system(_ t: String) -> ChatRequestMessage {
        ChatRequestMessage(role: "system", content: t, contentParts: nil, tool_calls: nil, tool_call_id: nil)
    }
    static func system(parts: [ContentPart]) -> ChatRequestMessage {
        ChatRequestMessage(role: "system", content: nil, contentParts: parts, tool_calls: nil, tool_call_id: nil)
    }
    static func user(_ t: String) -> ChatRequestMessage {
        ChatRequestMessage(role: "user", content: t, contentParts: nil, tool_calls: nil, tool_call_id: nil)
    }
    static func user(parts: [ContentPart]) -> ChatRequestMessage {
        ChatRequestMessage(role: "user", content: nil, contentParts: parts, tool_calls: nil, tool_call_id: nil)
    }
    static func assistant(_ t: String) -> ChatRequestMessage {
        ChatRequestMessage(role: "assistant", content: t, contentParts: nil, tool_calls: nil, tool_call_id: nil)
    }
    static func assistantToolCall(_ text: String?, _ calls: [CompletedToolCall]) -> ChatRequestMessage {
        ChatRequestMessage(
            role: "assistant",
            content: text,
            contentParts: nil,
            tool_calls: calls.map {
                ToolCallPayload(id: $0.id, type: "function", function: ToolFunctionPayload(name: $0.name, arguments: $0.arguments))
            },
            tool_call_id: nil
        )
    }
    static func toolResult(_ id: String, _ json: String) -> ChatRequestMessage {
        ChatRequestMessage(role: "tool", content: json, contentParts: nil, tool_calls: nil, tool_call_id: id)
    }
}

struct ToolCallPayload: Codable {
    var id: String
    var type: String
    var function: ToolFunctionPayload
}

struct ToolFunctionPayload: Codable {
    var name: String
    var arguments: String
}

// MARK: - 工具 Schema

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "无法解析 JSON 值")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

struct ToolSpec: Encodable {
    var type: String = "function"
    var function: ToolFunctionSpec
}

struct ToolFunctionSpec: Encodable {
    var name: String
    var description: String
    var parameters: JSONValue
}

// MARK: - 请求/响应编解码

struct ChatCompletionRequest: Encodable {
    struct ThinkingConfig: Encodable {
        var type: String
    }
    var model: String
    var messages: [ChatRequestMessage]
    var stream: Bool
    var temperature: Double?
    var max_tokens: Int?
    var tools: [ToolSpec]?
    var tool_choice: String?
    /// GLM 系等推理模型的关闭思考参数（仅当用户开启"关闭思考模式"时发送）
    var thinking: ThinkingConfig?
}

struct ChatCompletionChunk: Decodable {
    struct ChunkDelta: Decodable {
        var content: String?
        var tool_calls: [ToolCallDelta]?
    }
    struct ToolCallDelta: Decodable {
        var index: Int?
        var id: String?
        var function: ToolFunctionDelta?
    }
    struct ToolFunctionDelta: Decodable {
        var name: String?
        var arguments: String?
    }
    struct ChunkChoice: Decodable {
        var index: Int?
        var delta: ChunkDelta?
        var finish_reason: String?
    }
    struct ChunkUsage: Decodable {
        var total_tokens: Int?
    }
    struct APIErrorBody: Decodable {
        var message: String?
        var code: String?
        var type: String?
    }
    var choices: [ChunkChoice]?
    var usage: ChunkUsage?
    var error: APIErrorBody?
}

struct ChatCompletionResponse: Decodable {
    struct RespMessage: Decodable {
        var role: String?
        var content: String?
        var tool_calls: [RespToolCall]?
    }
    struct RespToolCall: Decodable {
        var id: String?
        var type: String?
        var function: ToolFunctionPayload?
    }
    struct Choice: Decodable {
        var index: Int?
        var message: RespMessage?
        var finish_reason: String?
    }
    var choices: [Choice]?
    var error: ChatCompletionChunk.APIErrorBody?
}

struct ModelsResponse: Decodable {
    struct ModelItem: Decodable { var id: String }
    var data: [ModelItem]?
}

// MARK: - 客户端

struct APIClient {

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 3600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 带一次自动重试的数据请求（应对本地网络/代理抖动）
    static func dataWithRetry(_ req: URLRequest, attempts: Int = 2) async throws -> (Data, URLResponse) {
        var lastError: Error = APIError.decoding("请求失败")
        for attempt in 0..<max(1, attempts) {
            do {
                return try await session.data(for: req)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }
            }
        }
        throw lastError
    }

    /// 归一化 Base URL：兼容带/不带 /v1、带/不带 /chat/completions 的写法
    static func endpoints(_ rawBase: String) -> (chat: String, models: String)? {
        var base = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, URL(string: base) != nil else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        if base.lowercased().hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }
        if !base.lowercased().hasSuffix("/v1") {
            base += "/v1"
        }
        return (base + "/chat/completions", base + "/models")
    }

    static func makeRequest(profile: APIProfile, urlString: String, method: String, body: Data?, sse: Bool) throws -> URLRequest {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL(urlString) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !profile.apiKey.isEmpty {
            req.setValue("Bearer \(profile.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if sse {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        req.httpBody = body
        return req
    }

    // MARK: 流式对话

    static func streamChat(
        profile: APIProfile,
        messages: [ChatRequestMessage],
        tools: [ToolSpec]?,
        temperatureOverride: Double? = nil
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let eps = endpoints(profile.baseURL) else { throw APIError.invalidURL(profile.baseURL) }
                    let body = ChatCompletionRequest(
                        model: profile.model,
                        messages: messages,
                        stream: true,
                        temperature: temperatureOverride ?? profile.temperature,
                        max_tokens: profile.maxTokens,
                        tools: tools,
                        tool_choice: tools == nil ? nil : "auto",
                        thinking: profile.disableThinking ? ChatCompletionRequest.ThinkingConfig(type: "disabled") : nil
                    )
                    let req = try makeRequest(
                        profile: profile,
                        urlString: eps.chat,
                        method: "POST",
                        body: try JSONEncoder().encode(body),
                        sse: true
                    )
                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.decoding("非 HTTP 响应")
                    }
                    if http.statusCode >= 400 {
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line
                            if errBody.count > 800 { break }
                        }
                        throw APIError.http(http.statusCode, String(errBody.prefix(800)))
                    }

                    var acc: [Int: (id: String, name: String, args: String)] = [:]
                    var finish: String?
                    var totalTokens: Int?
                    var streamError: Error?

                    // SSE 规范：同一事件的多个 data: 行需拼接后解析
                    var eventLines: [String] = []
                    func processEvent(_ lines: [String]) {
                        let payload = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !payload.isEmpty, payload != "[DONE]" else { return }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else { return }
                        if let err = chunk.error {
                            streamError = APIError.http(200, err.message ?? "未知错误")
                            return
                        }
                        if let usage = chunk.usage?.total_tokens { totalTokens = usage }
                        for choice in chunk.choices ?? [] {
                            if let d = choice.delta?.content, !d.isEmpty {
                                continuation.yield(.delta(d))
                            }
                            for tc in choice.delta?.tool_calls ?? [] {
                                let idx = tc.index ?? 0
                                var cur = acc[idx] ?? ("", "", "")
                                if let id = tc.id, !id.isEmpty { cur.id = id }
                                if let n = tc.function?.name, !n.isEmpty { cur.name = n }
                                if let a = tc.function?.arguments { cur.args += a }
                                acc[idx] = cur
                            }
                            if let fr = choice.finish_reason { finish = fr }
                        }
                    }

                    var sawDone = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw CancellationError() }
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            if !eventLines.isEmpty { processEvent(eventLines); eventLines = [] }
                            continue
                        }
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { sawDone = true; break }
                        eventLines.append(payload)
                    }
                    if !eventLines.isEmpty { processEvent(eventLines) }
                    _ = sawDone

                    if let e = streamError { throw e }

                    let calls: [CompletedToolCall] = acc.keys.sorted().compactMap { idx in
                        guard let c = acc[idx], !c.name.isEmpty else { return nil }
                        // 工具参数必须是合法 JSON；finish=length 时丢弃（截断）
                        let args = c.args.trimmingCharacters(in: .whitespaces)
                        let isValidJSON = args.isEmpty || (args.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }) != nil
                        guard isValidJSON, finish != "length" else { return nil }
                        return CompletedToolCall(
                            id: c.id.isEmpty ? "call_\(idx)" : c.id,
                            name: c.name,
                            arguments: args.isEmpty ? "{}" : args
                        )
                    }
                    if !calls.isEmpty {
                        continuation.yield(.toolCalls(calls))
                    }
                    continuation.yield(.finished(reason: finish, totalTokens: totalTokens))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 非流式单次调用（用于记忆整理）

    static func completeOnce(
        profile: APIProfile,
        messages: [ChatRequestMessage],
        tools: [ToolSpec]? = nil,
        temperature: Double? = nil
    ) async throws -> (text: String, toolCalls: [CompletedToolCall], finish: String?) {
        guard let eps = endpoints(profile.baseURL) else { throw APIError.invalidURL(profile.baseURL) }
        let body = ChatCompletionRequest(
            model: profile.model,
            messages: messages,
            stream: false,
            temperature: temperature ?? profile.temperature,
            max_tokens: profile.maxTokens,
            tools: tools,
            tool_choice: tools == nil ? nil : "auto",
            thinking: profile.disableThinking ? ChatCompletionRequest.ThinkingConfig(type: "disabled") : nil
        )
        let req = try makeRequest(
            profile: profile,
            urlString: eps.chat,
            method: "POST",
            body: try JSONEncoder().encode(body),
            sse: false
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding("非 HTTP 响应") }
        guard http.statusCode < 400 else {
            throw APIError.http(http.statusCode, String(decoding: data.prefix(800), as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        if let err = decoded.error {
            throw APIError.http(200, err.message ?? "未知错误")
        }
        guard let choice = decoded.choices?.first, let msg = choice.message else {
            throw APIError.decoding("响应缺少内容")
        }
        let calls = (msg.tool_calls ?? []).compactMap { tc -> CompletedToolCall? in
            guard let f = tc.function else { return nil }
            return CompletedToolCall(id: tc.id ?? "call_0", name: f.name, arguments: f.arguments)
        }
        return (msg.content ?? "", calls, choice.finish_reason)
    }

    // MARK: 模型列表 / 连接测试

    static func listModels(profile: APIProfile) async throws -> [String] {
        guard let eps = endpoints(profile.baseURL) else { throw APIError.invalidURL(profile.baseURL) }
        let req = try makeRequest(profile: profile, urlString: eps.models, method: "GET", body: nil, sse: false)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding("非 HTTP 响应") }
        guard http.statusCode < 400 else {
            throw APIError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        guard let ids = decoded.data?.map({ $0.id }), !ids.isEmpty else {
            throw APIError.decoding("模型列表为空")
        }
        return ids.sorted()
    }

    static func testConnection(profile: APIProfile) async throws -> String {
        do {
            let models = try await listModels(profile: profile)
            return "连接成功，共 \(models.count) 个可用模型"
        } catch {
            // 有些服务不开放 /models，退而验证一次极小对话
            let reply = try await completeOnce(
                profile: profile,
                messages: [.system("只回复：ok"), .user("ping")],
                temperature: 0
            )
            return reply.text.isEmpty ? "连接成功（对话可用）" : "连接成功（对话可用，模型列表不可用）"
        }
    }

    // MARK: 工具定义（记忆 + 真实世界能力）

    static let memoryTools: [ToolSpec] = [
        ToolSpec(function: ToolFunctionSpec(
            name: "save_memory",
            description: "把一条值得长期记住的信息保存为你的长期记忆（事实、偏好、约定、重要事件等）。不要重复保存已经存在的相同信息。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("要记住的信息，一句话概括")
                    ]),
                    "category": .object([
                        "type": .string("string"),
                        "enum": .array(["事实", "偏好", "事件", "关系", "约定", "情绪", "其他"].map { .string($0) }),
                        "description": .string("记忆分类")
                    ]),
                    "importance": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(5),
                        "description": .string("重要程度 1-5，5 为核心信息")
                    ]),
                    "pinned": .object([
                        "type": .string("boolean"),
                        "description": .string("是否为核心记忆（长期有效、每次对话都记得）")
                    ])
                ]),
                "required": .array([.string("content")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "search_memory",
            description: "在你的长期记忆中检索信息，返回最相关的若干条记忆。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("检索关键词或一句描述")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "get_weather",
            description: "查询某个城市的实时天气与未来三天预报。用户提到天气时使用，用城市名调用。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "city": .object([
                        "type": .string("string"),
                        "description": .string("城市名，如：北京、上海、杭州")
                    ])
                ]),
                "required": .array([.string("city")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "get_news",
            description: "查询最新新闻资讯，可指定话题；不指定话题时返回当前要闻。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "topic": .object([
                        "type": .string("string"),
                        "description": .string("新闻话题，如：科技、体育、AI；留空表示要闻")
                    ])
                ])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "play_music",
            description: "用本机音乐 App 播放一首歌。用户想听歌时使用。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("歌曲名")
                    ]),
                    "artist": .object([
                        "type": .string("string"),
                        "description": .string("歌手名（可选，用于精确匹配）")
                    ])
                ]),
                "required": .array([.string("title")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "stop_music",
            description: "停止本机音乐播放。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "get_current_time",
            description: "查询当前的日期、时间与星期。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "web_search",
            description: "联网搜索网页信息。当用户问及你不确定的事实、新闻细节、人物、词条等时使用，返回相关网页标题与摘要。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("搜索关键词")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "calculate",
            description: "精确计算数学表达式（加减乘除、括号、百分比）。涉及数字运算时使用，不要心算。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "expression": .object([
                        "type": .string("string"),
                        "description": .string("数学表达式，如：(12+8)*3、15%*200")
                    ])
                ]),
                "required": .array([.string("expression")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "random_number",
            description: "生成随机数。掷骰子（1-6）、抛硬币（正面/反面）、抽签、随机挑选时使用。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "min": .object([
                        "type": .string("integer"),
                        "description": .string("最小值，默认 1")
                    ]),
                    "max": .object([
                        "type": .string("integer"),
                        "description": .string("最大值，默认 100")
                    ]),
                    "label": .object([
                        "type": .string("string"),
                        "description": .string("用途说明，如：掷骰子、抛硬币、抽签")
                    ])
                ])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "set_reminder",
            description: "设定一个本地通知提醒，到点后系统弹窗提醒用户。用户说『X分钟后提醒我…』时使用。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "minutes": .object([
                        "type": .string("number"),
                        "description": .string("多少分钟后提醒")
                    ]),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string("提醒内容")
                    ])
                ]),
                "required": .array([.string("minutes"), .string("text")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "read_screen",
            description: "截取用户的屏幕并查看内容（需要用户在设置中开启屏幕读取）。用户说『看看我的屏幕』『截屏』或询问屏幕上内容时使用。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "mode": .object([
                        "type": .string("string"),
                        "enum": .array([.string("full"), .string("window")]),
                        "description": .string("full=整个屏幕（默认）；window=最前面的窗口")
                    ])
                ])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "open_url",
            description: "在系统浏览器中打开一个网址。用户说『帮我打开XX』时使用，url 填完整域名。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "url": .object([
                        "type": .string("string"),
                        "description": .string("网址，如 bilibili.com 或 https://example.com")
                    ])
                ]),
                "required": .array([.string("url")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "read_clipboard",
            description: "读取用户剪贴板中的文字或图片。用户说『看看剪贴板』『我复制了什么』时使用。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "system_info",
            description: "查询电脑的系统状态：系统版本、内存、磁盘剩余、电量、运行时长。用户问电脑状态/电量时使用。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "generate_image",
            description: "生成一张图片并展示给用户。用户想画图、生成海报、头像、插图时使用（免费，无需 Key）。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "prompt": .object([
                        "type": .string("string"),
                        "description": .string("图片描述，如：海边日落，有帆船和椰子树")
                    ]),
                    "width": .object([
                        "type": .string("integer"),
                        "description": .string("宽度，默认 768")
                    ]),
                    "height": .object([
                        "type": .string("integer"),
                        "description": .string("高度，默认 768")
                    ])
                ]),
                "required": .array([.string("prompt")])
            ])
        )),
        ToolSpec(function: ToolFunctionSpec(
            name: "make_call",
            description: "发起电话通话：可以是电话号码，或通讯录联系人姓名（按姓名查找号码）。macOS 会通过 iPhone 接续拨出，用户需在系统弹窗中确认。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "target": .object([
                        "type": .string("string"),
                        "description": .string("电话号码或联系人姓名")
                    ])
                ]),
                "required": .array([.string("target")])
            ])
        ))
    ]
}
