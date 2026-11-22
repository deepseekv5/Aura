import SwiftUI

/// 检查更新视图：可独立成 sheet，也可嵌入设置页
struct UpdateView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var checking = false
    @State private var info: UpdateService.UpdateInfo?
    @State private var error: String?
    @State private var downloading = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                Text("检查更新")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            Text("当前版本：v\(UpdateService.currentVersion)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let info {
                VStack(alignment: .leading, spacing: 8) {
                    Text("发现新版本 \(info.version)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                    ScrollView {
                        Text(info.notes.isEmpty ? "无更新说明" : info.notes)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)

                    HStack {
                        Button("在浏览器查看") {
                            NSWorkspace.shared.open(URL(string: info.htmlURL)!)
                        }
                        .controlSize(.small)
                        Spacer()
                        Button(downloading ? "下载中…" : "下载并安装") {
                            Task { await install(info) }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(downloading)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if !checking {
                Text(message ?? (error.map { "检查失败：\($0)" } ?? "尚未检查"))
                    .font(.system(size: 12))
                    .foregroundStyle(error == nil ? Color.secondary : Color.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }

            if checking {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在检查 GitHub Releases…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if info == nil && !checking {
                    Button("检查更新") { Task { await check() } }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
        .onAppear {
            Task { await check() }
        }
    }

    private func check() async {
        checking = true
        error = nil
        message = nil
        do {
            info = try await UpdateService.check()
            if info == nil { message = "你已是最新版本" }
        } catch {
            self.error = error.localizedDescription
        }
        checking = false
    }

    private func install(_ info: UpdateService.UpdateInfo) async {
        downloading = true
        message = "正在下载…"
        do {
            let newApp = try await UpdateService.download(info) { _ in }
            message = "正在安装…"
            _ = try await UpdateService.install(newApp: newApp)
        } catch {
            self.error = error.localizedDescription
        }
        downloading = false
    }
}
