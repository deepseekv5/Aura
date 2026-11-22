import Foundation

// MARK: - 角色

struct RoleProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#5B8DEF"
    /// 写实肖像文件名（存于 portraits/），空表示用首字头像
    var portraitPath: String = ""
    var persona: String = ""
    var scenario: String = ""
    var greeting: String = ""
    var tags: [String] = []
    /// 绑定的 API 配置；nil 表示跟随全局默认
    var apiProfileID: UUID?
    /// 覆盖模型名；空字符串表示使用配置默认
    var modelOverride: String = ""
    /// 覆盖温度；nil 表示使用配置默认
    var temperatureOverride: Double?
    var memoryEnabled: Bool = true
    var noEmojiReplies: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayName: String { name.isEmpty ? "未命名角色" : name }
}

// MARK: - 长期记忆

struct MemoryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var characterID: UUID
    var content: String
    var category: String = "其他"
    /// 1-5，5 为核心
    var importance: Int = 3
    var pinned: Bool = false
    /// ai / manual / summary
    var source: String = "manual"
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var useCount: Int = 0

    static let categories = ["事实", "偏好", "事件", "关系", "约定", "情绪", "其他"]

    var sourceLabel: String {
        switch source {
        case "ai": return "AI 写入"
        case "summary": return "对话整理"
        default: return "手动"
        }
    }
}

/// 记忆工具入参
struct MemoryToolArgs: Codable {
    var content: String
    var category: String?
    var importance: Int?
    var pinned: Bool?
}

/// 检索工具入参
struct SearchToolArgs: Codable {
    var query: String
}

/// 记忆整理的解析结果
struct MemoryDraft: Codable {
    var content: String
    var category: String?
    var importance: Int?
    var pinned: Bool?
}

// MARK: - 消息与会话

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable {
        case user, assistant
    }

    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date = Date()
    /// 群聊中发言的角色；单聊为 nil
    var speakerID: UUID?
    /// 该条回复中 AI 主动写入的记忆摘要
    var memoryNotes: [String] = []
    var modelUsed: String?
    /// 附带图片的文件名（存于数据目录 images/ 下），用于读图与生图展示
    var imagePaths: [String] = []

    // 兼容旧会话数据：缺失字段回退默认值
    init(role: Role, content: String, speakerID: UUID? = nil, memoryNotes: [String] = [], modelUsed: String? = nil, imagePaths: [String] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.speakerID = speakerID
        self.memoryNotes = memoryNotes
        self.modelUsed = modelUsed
        self.imagePaths = imagePaths
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, createdAt, speakerID, memoryNotes, modelUsed, imagePaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        if let roleStr = try c.decodeIfPresent(String.self, forKey: .role) {
            role = Role(rawValue: roleStr) ?? (roleStr == "assistant" ? .assistant : .user)
        } else {
            role = .user
        }
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        speakerID = try c.decodeIfPresent(UUID.self, forKey: .speakerID)
        memoryNotes = try c.decodeIfPresent([String].self, forKey: .memoryNotes) ?? []
        modelUsed = try c.decodeIfPresent(String.self, forKey: .modelUsed)
        imagePaths = try c.decodeIfPresent([String].self, forKey: .imagePaths) ?? []
    }
}

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// 单聊：角色 id；群聊：第一个成员（发起人）
    var characterID: UUID
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var isGroup: Bool = false
    var groupMemberIDs: [UUID] = []
    var pinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

// MARK: - API 配置

struct APIProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "新配置"
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
    var temperature: Double = 0.8
    var maxTokens: Int = 8192
    /// 关闭模型的深度思考（GLM 等推理模型直出思考内容时开启）
    var disableThinking: Bool = false
    var isDefault: Bool = false

    // 兼容旧配置：缺失字段回退默认值，绝不让整份配置解码失败
    init() {}

    init(
        name: String,
        baseURL: String = "",
        apiKey: String = "",
        model: String = "",
        temperature: Double = 0.8,
        maxTokens: Int = 8192,
        isDefault: Bool = false
    ) {
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.isDefault = isDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, model, temperature, maxTokens, disableThinking, isDefault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "新配置"
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.8
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 8192
        disableThinking = try c.decodeIfPresent(Bool.self, forKey: .disableThinking) ?? false
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

struct AppSettings: Codable {
    var profiles: [APIProfile] = []
    var activeProfileID: UUID?
    var demoMode: Bool = false
    var userName: String = ""
    var userBio: String = ""
    var noEmojiReplies: Bool = true
    /// 每轮注入的记忆条数
    var memoryTopK: Int = 8
    /// 上下文窗口大小（token），默认 1M
    var contextWindowTokens: Int = 1_000_000
    /// 是否自动压缩超限历史
    var contextAutoCompress: Bool = true
    /// 全局强调色（十六进制），空表示系统默认
    var accentColorHex: String = ""
    /// 朗读语速 0.4-1.0
    var speechRate: Double = 0.5
    /// 启动时自动检查更新
    var autoCheckUpdates: Bool = true
    /// 自动本地备份
    var autoBackup: Bool = true
    /// 自动 iCloud 备份
    var iCloudBackupEnabled: Bool = false

    // MiMo TTS 语音朗读
    var ttsAuto: Bool = false
    var ttsAPIKey: String = ""
    var ttsModel: String = "mimo-v2.5-tts"
    var ttsVoice: String = "mimo_default"
    /// 仅 voicedesign 模型使用
    var ttsVoiceDesign: String = ""
    var ttsFormat: String = "mp3"

    // 法律合规：已同意的协议版本（空表示未同意）
    var legalConsentVersion: String = ""

    // 屏幕读取
    var screenEnabled: Bool = false
    /// full = 整个屏幕；window = 最前面的窗口
    var screenMode: String = "full"
    /// 屏幕读取密码（盐 + SHA256），空表示未设密码
    var screenPasswordSalt: String = ""
    var screenPasswordHash: String = ""

    static let standard: AppSettings = {
        var s = AppSettings()
        s.profiles = [
            APIProfile(
                name: "默认配置",
                baseURL: "",
                apiKey: "",
                model: "",
                temperature: 0.8,
                maxTokens: 8192,
                isDefault: true
            )
        ]
        return s
    }()

    private enum CodingKeys: String, CodingKey {
        case profiles, activeProfileID, demoMode, userName, userBio, noEmojiReplies, memoryTopK, contextWindowTokens, contextAutoCompress
        case ttsAuto, ttsAPIKey, ttsModel, ttsVoice, ttsVoiceDesign, ttsFormat
        case accentColorHex, speechRate, autoCheckUpdates, autoBackup, iCloudBackupEnabled
        case screenEnabled, screenMode, screenPasswordSalt, screenPasswordHash, legalConsentVersion
    }

    // 兼容旧版配置文件：缺失字段回退默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decodeIfPresent([APIProfile].self, forKey: .profiles) ?? AppSettings.standard.profiles
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        demoMode = try c.decodeIfPresent(Bool.self, forKey: .demoMode) ?? false
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        userBio = try c.decodeIfPresent(String.self, forKey: .userBio) ?? ""
        noEmojiReplies = try c.decodeIfPresent(Bool.self, forKey: .noEmojiReplies) ?? true
        memoryTopK = try c.decodeIfPresent(Int.self, forKey: .memoryTopK) ?? 8
        contextWindowTokens = try c.decodeIfPresent(Int.self, forKey: .contextWindowTokens) ?? 1_000_000
        contextAutoCompress = try c.decodeIfPresent(Bool.self, forKey: .contextAutoCompress) ?? true
        ttsAuto = try c.decodeIfPresent(Bool.self, forKey: .ttsAuto) ?? false
        ttsAPIKey = try c.decodeIfPresent(String.self, forKey: .ttsAPIKey) ?? ""
        ttsModel = try c.decodeIfPresent(String.self, forKey: .ttsModel) ?? "mimo-v2.5-tts"
        ttsVoice = try c.decodeIfPresent(String.self, forKey: .ttsVoice) ?? "mimo_default"
        ttsVoiceDesign = try c.decodeIfPresent(String.self, forKey: .ttsVoiceDesign) ?? ""
        ttsFormat = try c.decodeIfPresent(String.self, forKey: .ttsFormat) ?? "mp3"
        accentColorHex = try c.decodeIfPresent(String.self, forKey: .accentColorHex) ?? ""
        speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? 0.5
        autoCheckUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? true
        autoBackup = try c.decodeIfPresent(Bool.self, forKey: .autoBackup) ?? true
        iCloudBackupEnabled = try c.decodeIfPresent(Bool.self, forKey: .iCloudBackupEnabled) ?? false
        screenEnabled = try c.decodeIfPresent(Bool.self, forKey: .screenEnabled) ?? false
        screenMode = try c.decodeIfPresent(String.self, forKey: .screenMode) ?? "full"
        screenPasswordSalt = try c.decodeIfPresent(String.self, forKey: .screenPasswordSalt) ?? ""
        screenPasswordHash = try c.decodeIfPresent(String.self, forKey: .screenPasswordHash) ?? ""
        legalConsentVersion = try c.decodeIfPresent(String.self, forKey: .legalConsentVersion) ?? ""
    }

    init() {}

    func activeProfile() -> APIProfile? {
        profiles.first { $0.id == activeProfileID }
            ?? profiles.first { $0.isDefault }
            ?? profiles.first
    }

    func profile(for character: RoleProfile) -> APIProfile? {
        if let pid = character.apiProfileID, let p = profiles.first(where: { $0.id == pid }) {
            return p
        }
        return activeProfile()
    }
}


// MARK: - 排序方式

enum MemorySort: String, CaseIterable, Identifiable {
    case newest = "最新"
    case importance = "重要度"
    case usage = "使用次数"
    case category = "分类"
    var id: String { rawValue }
}
