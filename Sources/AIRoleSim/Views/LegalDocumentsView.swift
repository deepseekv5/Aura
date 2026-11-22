import SwiftUI

/// 设置内法律文档查看器（原文来自 LegalDocuments，与仓库文档同步）
struct LegalDocumentsView: View {
    enum Mode {
        case terms, privacy
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        mode == .terms ? "用户服务协议" : "隐私政策"
    }

    private var text: String {
        mode == .terms ? LegalDocuments.terms : LegalDocuments.privacy
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: mode == .terms ? "doc.text" : "hand.raised.shield")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(16)

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }

            Divider()
            HStack {
                Text("Aura · 版本 v\(UpdateService.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 620, height: 640)
    }
}
