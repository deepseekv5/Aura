import Foundation
import AppKit

struct MessageHit: Identifiable, Hashable {
    let id: UUID
    let conversationID: UUID
    let conversationTitle: String
    let characterID: UUID
    let characterName: String
    let messageID: UUID
    let snippet: String
    let date: Date
}

struct SearchResults {
    var characters: [RoleProfile] = []
    var memories: [MemoryEntry] = []
    var messages: [MessageHit] = []

    var isEmpty: Bool { characters.isEmpty && memories.isEmpty && messages.isEmpty }
}

@MainActor
final class AppStore: ObservableObject {

    // MARK: - 状态

    @Published var characters: [RoleProfile] = []
    @Published var conversations: [Conversation] = []
    @Published var memories: [MemoryEntry] = []
    @Published var settings: AppSettings = .standard {
        didSet { persist(settings, to: configURL, restrictive: true) }
    }

    // 选择与界面状态
    @Published var selectedCharacterID: UUID?
    @Published var selectedConversationID: UUID?
    @Published var showMemoryInspector = false
    @Published var inspectorQuery = ""
    @Published var showCharacterEditor = false
    @Published var editingCharacterID: UUID?
    @Published var showGroupSetup = false
    @Published var showSearch = false
    /// 屏幕读取是否已用密码解锁（内存态，重启后需重新解锁）
    @Published var screenUnlocked = false

    /// 使用统计
    struct UsageStats {
        var totalMessages: Int = 0
        var userMessages: Int = 0
        var assistantMessages: Int = 0
        var totalMemories: Int = 0
        var daysSinceFirstUse: Int = 0
    }

    func usageStats() -> UsageStats {
        let all = conversations.flatMap { $0.messages }
        let first = conversations.map { $0.createdAt }.min() ?? Date()
        return UsageStats(
            totalMessages: all.count,
            userMessages: all.filter { $0.role == .user }.count,
            assistantMessages: all.filter { $0.role == .assistant }.count,
            totalMemories: memories.count,
            daysSinceFirstUse: max(1, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 1)
        )
    }

    /// 自动本地备份（每次数据变更后调用；保留最近 3 份）
    func autoLocalBackup() {
        guard let data = exportAllData() else { return }
        let dir = dataDir.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let file = dir.appendingPathComponent("auto-\(fmt.string(from: Date())).json")
        try? data.write(to: file, options: .atomic)
        // 只保留最近 3 份
        let files: [URL] = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("auto-") }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return da > db
            }
        for old in files.dropFirst(3) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    let dataDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - 初始化

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDir = support.appendingPathComponent("AIRoleSim", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dataDir.appendingPathComponent("images", isDirectory: true), withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        loadAll()
        // init 期间赋值不触发 didSet，首次运行主动落盘一份默认配置
        persist(settings, to: configURL, restrictive: true)
    }

    var imagesDir: URL { dataDir.appendingPathComponent("images", isDirectory: true) }

    /// 保存图片，返回文件名；失败返回 nil
    func saveImageData(_ data: Data) -> String? {
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        let url = imagesDir.appendingPathComponent(name)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return name
    }

    func imageURL(named name: String) -> URL {
        imagesDir.appendingPathComponent(name)
    }

    private var charactersURL: URL { dataDir.appendingPathComponent("characters.json") }
    private var conversationsURL: URL { dataDir.appendingPathComponent("conversations.json") }
    private var memoriesURL: URL { dataDir.appendingPathComponent("memories.json") }
    private var configURL: URL { dataDir.appendingPathComponent("config.json") }

    private func loadAll() {
        if let data = try? Data(contentsOf: configURL) {
            settings = (try? decoder.decode(AppSettings.self, from: data)) ?? .standard
        }
        if let data = try? Data(contentsOf: charactersURL) {
            characters = (try? decoder.decode([RoleProfile].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: conversationsURL) {
            conversations = (try? decoder.decode([Conversation].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: memoriesURL) {
            memories = (try? decoder.decode([MemoryEntry].self, from: data)) ?? []
        }
        // 历史迁移：旧版默认 2048，统一提升到 8192
        for i in settings.profiles.indices where settings.profiles[i].maxTokens < 4096 {
            settings.profiles[i].maxTokens = 8192
        }
    }

    private func persist<T: Encodable>(_ value: T, to url: URL, restrictive: Bool = false) {
        guard let data = try? encoder.encode(value) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
            if restrictive {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
    }

    private func persistCharacters() { persist(characters, to: charactersURL) }
    private func persistConversations() { persist(conversations, to: conversationsURL) }
    private func persistMemories() { persist(memories, to: memoriesURL) }

    // MARK: - 角色管理

    func addCharacter(_ c: RoleProfile) {
        characters.append(c)
        persistCharacters()
    }

    func updateCharacter(_ c: RoleProfile) {
        if let i = characters.firstIndex(where: { $0.id == c.id }) {
            var updated = c
            updated.updatedAt = Date()
            characters[i] = updated
            persistCharacters()
        }
    }

    func deleteCharacter(_ c: RoleProfile) {
        characters.removeAll { $0.id == c.id }
        conversations.removeAll { $0.characterID == c.id || c.id != $0.characterID && $0.groupMemberIDs.contains(c.id) && $0.groupMemberIDs.count <= 1 }
        memories.removeAll { $0.characterID == c.id }
        persistCharacters()
        persistConversations()
        persistMemories()
        if selectedCharacterID == c.id {
            selectedCharacterID = nil
            selectedConversationID = nil
        }
    }

    func duplicateCharacter(_ c: RoleProfile) {
        var copy = c
        copy.id = UUID()
        copy.name = c.name + " 副本"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        addCharacter(copy)
    }

    func character(id: UUID?) -> RoleProfile? {
        guard let id else { return nil }
        return characters.first { $0.id == id }
    }

    func selectedCharacter() -> RoleProfile? {
        character(id: selectedCharacterID)
    }

    func selectCharacter(_ id: UUID) {
        selectedCharacterID = id
        inspectorQuery = ""
        selectedConversationID = conversations(for: id).first?.id
    }

    func beginNewCharacter() {
        editingCharacterID = nil
        showCharacterEditor = true
    }

    func editCharacter(_ id: UUID) {
        editingCharacterID = id
        showCharacterEditor = true
    }

    // MARK: - 会话管理

    func conversations(for characterID: UUID) -> [Conversation] {
        conversations
            .filter { $0.characterID == characterID }
            .sorted { a, b in
                if a.pinned != b.pinned { return a.pinned }
                return a.updatedAt > b.updatedAt
            }
    }

    func conversation(id: UUID?) -> Conversation? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
    }

    @discardableResult
    func createConversation(characterID: UUID, isGroup: Bool = false, members: [UUID] = []) -> Conversation {
        var c = Conversation(characterID: characterID, isGroup: isGroup, groupMemberIDs: isGroup ? members : [])
        if isGroup {
            let names = members.compactMap { character(id: $0)?.displayName }
            c.title = "多人对话 · " + names.joined(separator: " / ")
        }
        conversations.append(c)
        persistConversations()
        selectedConversationID = c.id
        return c
    }

    func newConversationForSelection() {
        guard let id = selectedCharacterID else { return }
        let c = createConversation(characterID: id)
        if let char = character(id: id), !char.greeting.isEmpty {
            appendMessage(to: c.id, ChatMessage(role: .assistant, content: char.greeting, speakerID: char.id, modelUsed: "开场白"))
        }
    }

    func appendMessage(to conversationID: UUID, _ m: ChatMessage) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[i].messages.append(m)
        conversations[i].updatedAt = Date()
        if !conversations[i].isGroup, m.role == .user, conversations[i].title == "新对话" {
            conversations[i].title = String(m.content.prefix(14))
        }
        persistConversations()
    }

    func updateMessage(conversationID: UUID, messageID: UUID, content: String) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationID }),
              let j = conversations[i].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[i].messages[j].content = content
        conversations[i].updatedAt = Date()
        persistConversations()
    }

    func deleteMessage(conversationID: UUID, messageID: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[i].messages.removeAll { $0.id == messageID }
        conversations[i].updatedAt = Date()
        persistConversations()
    }

    func replaceConversation(_ c: Conversation) {
        if let i = conversations.firstIndex(where: { $0.id == c.id }) {
            conversations[i] = c
            persistConversations()
        }
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        persistConversations()
        if selectedConversationID == id {
            selectedConversationID = selectedCharacterID.map { conversations(for: $0).first?.id } ?? nil
        }
    }

    // MARK: - 记忆管理

    func memories(for characterID: UUID) -> [MemoryEntry] {
        memories
            .filter { $0.characterID == characterID }
            .sorted { a, b in
                if a.pinned != b.pinned { return a.pinned }
                return a.createdAt > b.createdAt
            }
    }

    @discardableResult
    func addMemory(
        characterID: UUID,
        content: String,
        category: String,
        importance: Int,
        pinned: Bool,
        source: String
    ) -> MemoryEntry {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // 内容去重：AI 重复保存时不重复落库
        if let existing = memories.first(where: { $0.characterID == characterID && $0.content == trimmed }) {
            return existing
        }
        let m = MemoryEntry(
            characterID: characterID,
            content: trimmed,
            category: category.isEmpty ? "其他" : category,
            importance: min(max(importance, 1), 5),
            pinned: pinned,
            source: source
        )
        memories.append(m)
        persistMemories()
        return m
    }

    func updateMemory(_ m: MemoryEntry) {
        if let i = memories.firstIndex(where: { $0.id == m.id }) {
            memories[i] = m
            persistMemories()
        }
    }

    func deleteMemory(_ m: MemoryEntry) {
        memories.removeAll { $0.id == m.id }
        persistMemories()
    }

    func togglePin(_ m: MemoryEntry) {
        var copy = m
        copy.pinned.toggle()
        updateMemory(copy)
    }

    func clearMemories(characterID: UUID) {
        memories.removeAll { $0.characterID == characterID }
        persistMemories()
    }

    func recordMemoryUse(ids: [UUID]) {
        var changed = false
        for id in ids {
            if let i = memories.firstIndex(where: { $0.id == id }) {
                memories[i].useCount += 1
                memories[i].lastUsedAt = Date()
                changed = true
            }
        }
        if changed { persistMemories() }
    }

    // MARK: - 记忆整理（把近期对话提炼为结构化记忆）

    func summarizeMemories(for characterID: UUID) async throws -> Int {
        guard let char = character(id: characterID) else { return 0 }
        let convo = conversations(for: characterID).first
        let recent = Array((convo?.messages ?? []).suffix(40))
        guard !recent.isEmpty else { return 0 }

        let who: (ChatMessage) -> String = { [weak self] msg in
            guard let self else { return char.displayName }
            if msg.role == .user {
                return self.settings.userName.isEmpty ? "用户" : self.settings.userName
            }
            if let sp = msg.speakerID, let name = self.character(id: sp)?.displayName {
                return name
            }
            return char.displayName
        }
        let transcript = recent.map { "\(who($0))：\($0.content)" }.joined(separator: "\n")

        var drafts: [MemoryDraft] = []
        let profile = effectiveProfile(for: char)
        if !settings.demoMode, let profile {
            let prompt = PromptBuilder.summarizePrompt(characterName: char.displayName, transcript: transcript)
            let result = try await APIClient.completeOnce(
                profile: profile,
                messages: [.system("你是一个记忆整理助手，只输出 JSON。"), .user(prompt)],
                temperature: 0.2
            )
            drafts = Self.parseDrafts(result.text)
        } else {
            // 演示模式：直接从用户消息构造
            drafts = recent.filter { $0.role == .user }.suffix(3).map {
                MemoryDraft(content: "用户提到：" + String($0.content.prefix(30)), category: "事件", importance: 2, pinned: false)
            }
        }

        var added = 0
        for d in drafts where !d.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let before = memories.count
            addMemory(
                characterID: characterID,
                content: d.content,
                category: d.category ?? "其他",
                importance: d.importance ?? 3,
                pinned: d.pinned ?? false,
                source: "summary"
            )
            if memories.count > before { added += 1 }
        }
        return added
    }

    static func parseDrafts(_ text: String) -> [MemoryDraft] {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 剥掉 markdown 代码围栏
        if t.hasPrefix("```") {
            if let firstNewline = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNewline)...])
            }
            if let fenceRange = t.range(of: "```", options: .backwards) {
                t = String(t[..<fenceRange.lowerBound])
            }
        }
        func tryDecode(_ s: String) -> [MemoryDraft]? {
            guard let data = s.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([MemoryDraft].self, from: data)
        }
        if let arr = tryDecode(t) { return arr }
        if let s = t.firstIndex(of: "["), let e = t.lastIndex(of: "]"), s < e, let arr = tryDecode(String(t[s...e])) {
            return arr
        }
        return []
    }

    // MARK: - 配置

    /// 是否存在可用的 API 配置（非演示模式下未配置则应弹出引导）
    func hasUsableAPIConfig() -> Bool {
        guard let p = settings.activeProfile() else { return false }
        return !p.baseURL.isEmpty && !p.apiKey.isEmpty && !p.model.isEmpty
    }

    func effectiveProfile(for character: RoleProfile) -> APIProfile? {
        guard let p = settings.profile(for: character) else { return nil }
        guard !p.baseURL.isEmpty, !p.model.isEmpty else { return nil }
        return p
    }

    func setDefaultProfile(_ id: UUID) {
        for i in settings.profiles.indices {
            settings.profiles[i].isDefault = (settings.profiles[i].id == id)
        }
        settings.activeProfileID = id
    }

    // MARK: - 全局搜索

    func searchAll(_ query: String) -> SearchResults {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SearchResults() }
        let ql = q.lowercased()
        var r = SearchResults()

        r.characters = characters.filter {
            $0.name.lowercased().contains(ql) || $0.persona.lowercased().contains(ql) || $0.tags.contains { $0.lowercased().contains(ql) }
        }
        r.memories = Array(
            memories.filter { $0.content.lowercased().contains(ql) }
                .sorted { $0.importance > $1.importance }
                .prefix(20)
        )
        outer: for c in conversations {
            let charName = character(id: c.characterID)?.displayName ?? "角色"
            for m in c.messages where m.content.lowercased().contains(ql) {
                r.messages.append(MessageHit(
                    id: m.id,
                    conversationID: c.id,
                    conversationTitle: c.title,
                    characterID: c.characterID,
                    characterName: charName,
                    messageID: m.id,
                    snippet: String(m.content.prefix(80)),
                    date: m.createdAt
                ))
                if r.messages.count >= 30 { break outer }
            }
        }
        return r
    }

    // MARK: - 导出

    func exportMarkdown(conversationID: UUID) -> String {
        guard let c = conversation(id: conversationID) else { return "" }
        let owner = character(id: c.characterID)?.displayName ?? "角色"
        var lines: [String] = ["# \(c.title)", "", "- 角色：\(owner)", "- 导出时间：\(Date().formatted(date: .abbreviated, time: .shortened))", ""]
        for m in c.messages {
            let name: String
            if m.role == .user {
                name = settings.userName.isEmpty ? "我" : settings.userName
            } else if let sp = m.speakerID, let n = character(id: sp)?.displayName {
                name = n
            } else {
                name = owner
            }
            lines.append("**\(name)**（\(m.createdAt.formatted(date: .abbreviated, time: .shortened))）：")
            lines.append(m.content)
            if !m.memoryNotes.isEmpty {
                lines.append("> 已记忆：" + m.memoryNotes.joined(separator: "；"))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func openDataFolder() {
        NSWorkspace.shared.open(dataDir)
    }

    /// 导出全部用户数据为 JSON（不含图片二进制，仅文件名；含全部设置）
    func exportAllData() -> Data? {
        let payload: [String: Any] = [
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "settings": (try? JSONEncoder().encode(settings)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:],
            "characters": (try? JSONEncoder().encode(characters)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [],
            "conversations": (try? JSONEncoder().encode(conversations)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [],
            "memories": (try? JSONEncoder().encode(memories)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? []
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    /// 从导出的 JSON 恢复数据（覆盖当前数据）
    func importAllData(_ data: Data) -> Bool {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ch = obj["characters"] as? [[String: Any]],
              let co = obj["conversations"] as? [[String: Any]],
              let me = obj["memories"] as? [[String: Any]] else { return false }
        let d1 = (try? JSONSerialization.data(withJSONObject: ch)) ?? Data()
        let d2 = (try? JSONSerialization.data(withJSONObject: co)) ?? Data()
        let d3 = (try? JSONSerialization.data(withJSONObject: me)) ?? Data()
        guard let newChars = try? decoder.decode([RoleProfile].self, from: d1),
              let newConvos = try? decoder.decode([Conversation].self, from: d2),
              let newMems = try? decoder.decode([MemoryEntry].self, from: d3) else { return false }
        characters = newChars
        conversations = newConvos
        memories = newMems
        if let setObj = obj["settings"] as? [String: Any],
           let sd = try? JSONSerialization.data(withJSONObject: setObj),
           let newSettings = try? decoder.decode(AppSettings.self, from: sd) {
            settings = newSettings
        }
        persistCharacters(); persistConversations(); persistMemories()
        return true
    }

    /// 切换会话置顶
    func toggleConversationPin(_ id: UUID) {
        if let i = conversations.firstIndex(where: { $0.id == id }) {
            conversations[i].pinned.toggle()
            persistConversations()
        }
    }
}
