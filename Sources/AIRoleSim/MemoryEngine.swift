import Foundation

/// 长期记忆检索引擎：关键词命中 + 重要性 + 时间新近度打分，零外部依赖。
struct MemoryEngine {

    // 常见虚词停用，避免噪声命中
    private static let stopwords: Set<String> = [
        "的", "了", "是", "我", "你", "他", "她", "它", "们", "在", "和", "有", "不",
        "这", "那", "就", "都", "也", "人", "说", "要", "会", "能", "着", "好", "很",
        "上", "下", "中", "里", "个", "吗", "呢", "吧", "啊", "呀", "哦", "嘛", "么",
        "自己", "什么", "所以", "但是", "因为", "如果", "还是", "而且", "然后"
    ]

    /// 分词：英文按词，中文按二元组（保留单个汉字短语）
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var latin = ""
        var cjk = ""

        func flushLatin() {
            if latin.count >= 2 { tokens.append(latin.lowercased()) }
            latin = ""
        }
        func flushCJK() {
            let chars = Array(cjk)
            if chars.count == 1 {
                tokens.append(cjk)
            } else if chars.count == 2 {
                tokens.append(cjk)
            } else if chars.count > 2 {
                for i in 0...(chars.count - 2) {
                    tokens.append(String(chars[i...(i + 1)]))
                }
            }
            cjk = ""
        }

        for ch in text {
            if ch.isLetter || ch.isNumber {
                if isCJK(ch) {
                    flushLatin()
                    cjk.append(ch)
                } else {
                    flushCJK()
                    latin.append(ch)
                }
            } else {
                flushLatin()
                flushCJK()
            }
        }
        flushLatin()
        flushCJK()

        return Array(Set(tokens)).filter { token in
            guard token.count <= 2 else { return true }
            return !stopwords.contains(token)
        }
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1, let s = ch.unicodeScalars.first else { return false }
        let v = s.value
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v)
    }

    /// 关键词命中加分（独立计算，便于判断是否发生了语义匹配）
    static func keywordBonus(_ m: MemoryEntry, queryTokens: Set<String>) -> Double {
        var bonus = 0.0
        for t in queryTokens.sorted() {
            if t.count < 2 { continue }
            if m.content.localizedCaseInsensitiveContains(t) {
                bonus += t.count >= 3 ? 8 : 6
            }
            if bonus >= 30 { break }
        }
        return bonus
    }

    static func score(_ m: MemoryEntry, queryTokens: Set<String>, now: Date) -> Double {
        var s = Double(m.importance) * 1.2
        if m.pinned { s += 40 }
        let ref = m.lastUsedAt ?? m.createdAt
        let days = max(0, now.timeIntervalSince(ref) / 86400)
        s += exp(-days / 45) * 6
        s += min(Double(m.useCount), 10) * 0.4
        s += keywordBonus(m, queryTokens: queryTokens)
        return s
    }

    /// 选取最相关的记忆：有关键词命中时取命中的 topN，否则按重要性+新近度兜底
    static func relevant(
        from entries: [MemoryEntry],
        characterID: UUID,
        query: String,
        limit: Int,
        now: Date = Date()
    ) -> [MemoryEntry] {
        let mine = entries.filter { $0.characterID == characterID }
        guard !mine.isEmpty else { return [] }
        // 稳定顺序：排序 token 后累加，保证同查询同结果
        let tokens = Set(tokenize(query))
        let now0 = now

        let scored = mine.map { m -> (MemoryEntry, Double, Double) in
            let bonus = keywordBonus(m, queryTokens: tokens) // 只算一次
            var base = Double(m.importance) * 1.2
            if m.pinned { base += 12 } // 置顶加权，而非无上限附带
            let ref = m.lastUsedAt ?? m.createdAt
            let days = max(0, now0.timeIntervalSince(ref) / 86400)
            base += exp(-days / 45) * 6
            base += min(Double(m.useCount), 10) * 0.4
            return (m, base + bonus, bonus)
        }

        // 统一按总分排序取前 limit，置顶已加权，结果不超上限
        let picked = scored
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.id.uuidString < b.0.id.uuidString // 稳定 tiebreak
            }
            .prefix(max(1, limit))
            .map { $0.0 }
        return picked
    }

    /// 生成注入系统提示的记忆文本块
    static func contextBlock(
        entries: [MemoryEntry],
        characterID: UUID,
        query: String,
        topK: Int,
        now: Date = Date()
    ) -> String {
        let picked = relevant(from: entries, characterID: characterID, query: query, limit: max(3, topK), now: now)
        guard !picked.isEmpty else { return "（暂无长期记忆，你们的交流才刚刚开始。）" }
        return picked
            .map { "[\($0.category)·重要度\($0.importance)] \($0.content)" }
            .joined(separator: "\n")
    }
}
