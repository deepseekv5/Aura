import Foundation

/// 上下文窗口管理：token 估算、用量统计、按预算裁剪与折叠压缩
struct ContextManager {

    struct Usage {
        var estimatedTokens: Int
        var budget: Int
        var fraction: Double
        var messageCount: Int
        var truncatedCount: Int
        var compressed: Bool

        var percentText: String {
            String(format: "%.1f%%", min(1.0, fraction) * 100)
        }
    }

    /// 粗略 token 估算：中文按 1.5 字符/token，英文按 4 字符/token
    static func estimateTokens(_ text: String) -> Int {
        var cjk = 0
        var other = 0
        for ch in text.unicodeScalars {
            let v = ch.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xAC00...0xD7AF).contains(v) {
                cjk += 1
            } else {
                other += 1
            }
        }
        return Int(ceil(Double(cjk) / 1.5 + Double(other) / 4.0)) + 4 // 消息开销
    }

    static func estimateMessages(_ messages: [ChatRequestMessage]) -> Int {
        messages.reduce(0) { sum, m in
            let text = (m.content ?? "") + (m.contentParts?.compactMap { $0.text }.joined() ?? "")
            return sum + estimateTokens(text)
        }
    }

    /// 统计本轮请求的上下文用量
    static func usage(messages: [ChatRequestMessage], budget: Int, truncated: Int = 0, compressed: Bool = false) -> Usage {
        let tokens = estimateMessages(messages)
        return Usage(
            estimatedTokens: tokens,
            budget: budget,
            fraction: budget > 0 ? Double(tokens) / Double(budget) : 0,
            messageCount: messages.count,
            truncatedCount: truncated,
            compressed: compressed
        )
    }

    /// 按预算裁剪历史：从旧到新保留，超限时折叠旧消息为一条摘要（或丢弃）
    static func fitHistory(
        allMessages: [ChatMessage],
        systemTokens: Int,
        memoryTokens: Int,
        budget: Int,
        autoCompress: Bool,
        maxImages: Int = 8,
        imageTokenCost: Int = 1400
    ) -> (messages: [ChatMessage], truncated: Int, compressed: Bool) {
        let reserve = systemTokens + memoryTokens + 2048 // 给回复留空间
        let available = max(0, budget - reserve)
        var used = 0
        var kept: [ChatMessage] = []
        var imageCount = 0

        // 从最新往旧遍历，优先保留近期消息
        for m in allMessages.reversed() {
            var cost = estimateTokens(m.content)
            if !m.imagePaths.isEmpty {
                for path in m.imagePaths where imageCount < maxImages {
                    cost += imageTokenCost
                    imageCount += 1
                }
            }
            if used + cost > available {
                return (kept.reversed(), allMessages.count - kept.count, autoCompress)
            }
            used += cost
            kept.append(m)
        }
        return (kept.reversed(), 0, false)
    }
}
