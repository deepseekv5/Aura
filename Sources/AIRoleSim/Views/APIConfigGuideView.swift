import SwiftUI

/// API 配置引导：默认 API 模式下，未配置任何 API 时弹出，引导用户完成配置
struct APIConfigGuideView: View {
    @EnvironmentObject var store: AppStore
    let onDone: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "network")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            Text("配置你的 AI 服务")
                .font(.system(size: 19, weight: .semibold))
            Text("Aura 默认使用你自己的 API，所有数据仅存于本地。请填写任意 OpenAI 兼容服务（OpenAI、DeepSeek、智谱、Kimi、OpenRouter、中转站等）的配置。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 10) {
                guideRow(number: "1", text: "填入 Base URL（如 https://api.deepseek.com）")
                guideRow(number: "2", text: "填入 API Key 与模型名")
                guideRow(number: "3", text: "可选：点拉取模型列表自动选择")
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    openSettings()
                    onDone()
                } label: {
                    Text("去设置")
                        .frame(width: 110)
                }
                .buttonStyle(.glassProminent)

                Button {
                    store.settings.demoMode = true
                    onDone()
                } label: {
                    Text("先用演示模式")
                        .frame(width: 130)
                }
                .buttonStyle(.glass)
            }

            Text("演示模式使用本地模拟回复，无需 API Key；天气等公共工具仍使用真实数据。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(26)
        .frame(width: 480)
    }

    private func guideRow(number: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 12))
        }
    }
}
