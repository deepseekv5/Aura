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
    /// 写实肖像文件名（存在时优先显示照片）
    var portraitPath: String = ""

    var body: some View {
        ZStack {
            if !portraitPath.isEmpty, let img = portraitImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: Color(hex: colorHex).opacity(0.3), radius: size * 0.15, y: size * 0.06)
                    .accessibilityLabel("\(text) 的肖像")
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var portraitImage: NSImage? {
        guard let url = AppStore.portraitURLShared(named: portraitPath) else { return nil }
        return NSImage(contentsOf: url)
    }

    @ViewBuilder
    private var placeholder: some View {
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

// MARK: - 语义化视觉组件（统一全项目质感）

/// 环境光晕：柔和的彩色光斑，用于背景层次
struct AmbientGlow: View {
    let color: Color
    var radius: CGFloat = 140
    var opacity: Double = 0.10

    var body: some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: radius, height: radius)
            .blur(radius: radius * 0.45)
            .allowsHitTesting(false)
    }
}

/// 强调卡片：微渐变 + 细描边 + 柔和投影
struct ElevatedCard<Content: View>: View {
    var tint: Color = .accentColor
    let content: Content

    init(tint: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tint.opacity(0.25), Color.white.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: 1
                    )
            }
            .shadow(color: tint.opacity(0.10), radius: 12, y: 4)
    }
}

/// 渐变细分隔线
struct GradientDivider: View {
    var color: Color = .accentColor

    var body: some View {
        LinearGradient(
            colors: [Color.clear, color.opacity(0.35), Color.clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }
}

/// 状态徽标（用于版本、用量、模式等）
struct StatusBadge: View {
    let text: String
    var color: Color = .accentColor
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9))
            }
            Text(text).font(.system(size: 9.5, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.10), in: Capsule())
    }
}
