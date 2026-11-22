import SwiftUI

// MARK: - 颜色

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self.init(
                red: Double((v >> 16) & 0xFF) / 255,
                green: Double((v >> 8) & 0xFF) / 255,
                blue: Double(v & 0xFF) / 255
            )
        } else {
            self.init(red: 0.4, green: 0.5, blue: 0.9)
        }
    }
}

enum Palette {
    static let swatches = ["#5B8DEF", "#7C6AF0", "#E36BAE", "#E0605E", "#E39A3B", "#3BA55D", "#2FA3A0", "#8A8F98"]
    static func random() -> String { swatches.randomElement() ?? "#5B8DEF" }
}

// MARK: - 首字头像（无 emoji，用名字首字 + 主题色）

struct Monogram: View {
    let text: String
    let colorHex: String
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: colorHex).opacity(0.9), Color(hex: colorHex).opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(prefix)
                .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: colorHex).opacity(0.35), radius: size * 0.18, y: size * 0.07)
    }

    private var prefix: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.first
        return first.map { String($0) } ?? "?"
    }
}

// MARK: - 玻璃面板修饰

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassPanel(_ cornerRadius: CGFloat) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

// MARK: - 记忆提示条（AI 写入记忆时显示）

struct MemoryChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain")
                .font(.system(size: 8.5, weight: .medium))
            Text(text)
                .font(.system(size: 10.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .foregroundStyle(.secondary)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - 重要度圆点

struct ImportanceDots: View {
    let value: Int

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < value ? Color.primary.opacity(0.55) : Color.primary.opacity(0.12))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
