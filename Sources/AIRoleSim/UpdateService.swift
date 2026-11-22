import Foundation
import AppKit

extension Notification.Name {
    static let showUpdateView = Notification.Name("showUpdateView")
}

// MARK: - App 内自更新（GitHub Releases）
// 流程：GET /repos/{owner}/{repo}/releases/latest → 比较版本 → 下载 zip →
//       解压到临时目录 → 用 FileManager 原子替换 ~/.local/share 或 /Applications 中的 app。
// 若当前 app 位于系统只读位置（如 /Applications），替换为「下载新版 + 打开访达 + 提示手动替换」。

enum UpdateService {

    struct Release: Decodable {
        var tag_name: String
        var html_url: String
        var body: String?
        struct Asset: Decodable {
            var name: String
            var browser_download_url: String
            var size: Int
        }
        var assets: [Asset]
    }

    struct UpdateInfo {
        var version: String
        var notes: String
        var downloadURL: URL
        var htmlURL: String
    }

    static let repo = "deepseekv5/Aura"
    static let currentVersion = "1.1.1"

    /// 检查更新（仅访问固定 GitHub API 主机，HTTPS）
    static func check() async throws -> UpdateInfo? {
        let endpoint = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https", url.host?.lowercased() == "api.github.com" else {
            throw APIError.invalidURL(endpoint)
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, resp) = try await APIClient.dataWithRetry(req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "检查更新失败")
        }
        let release = try JSONDecoder().decode(Release.self, from: data)

        // 版本比较：语义版本号数值比较
        guard versionNumber(release.tag_name) > versionNumber(currentVersion) else { return nil }

        // 优先 macOS zip asset
        guard let asset = release.assets.first(where: { $0.name.lowercased().contains("macos") && $0.name.lowercased().hasSuffix(".zip") })
                ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            throw APIError.decoding("发行版未找到 macOS 安装包")
        }
        guard let dl = URL(string: asset.browser_download_url), dl.scheme?.lowercased() == "https", dl.host?.lowercased() == "github.com" else {
            throw APIError.invalidURL(asset.browser_download_url)
        }
        return UpdateInfo(
            version: release.tag_name,
            notes: String((release.body ?? "").prefix(600)),
            downloadURL: dl,
            htmlURL: release.html_url
        )
    }

    private static func versionNumber(_ s: String) -> Int {
        let nums = s.replacingOccurrences(of: "v", with: "")
            .split(separator: ".")
            .compactMap { Int($0) }
        var v = 0
        for (i, n) in nums.prefix(3).enumerated() {
            v += n * [1_000_000, 1_000, 1][i]
        }
        return v
    }

    /// 下载更新并返回解压后的 .app 路径
    static func download(_ info: UpdateInfo, progress: @escaping (Double) -> Void) async throws -> URL {
        let (data, resp) = try await APIClient.dataWithRetry(URLRequest(url: info.downloadURL))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "下载失败")
        }
        progress(1.0)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let zip = tmp.appendingPathComponent("update.zip")
        try data.write(to: zip)

        // 用 ditto 解压（macOS 原生，保留资源分支）
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, tmp.path]
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw APIError.decoding("解压失败") }

        let contents = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw APIError.decoding("安装包中没有找到 .app")
        }
        return app
    }

    /// 安装更新：若当前 app 可写则原子替换并重启；否则提示手动
    @discardableResult
    static func install(newApp: URL) async throws -> Bool {
        let bundle = Bundle.main.bundleURL
        let parent = bundle.deletingLastPathComponent()

        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            // /Applications 等只读位置：打开访达 + 提示手动替换
            await MainActor.run {
                NSWorkspace.shared.open(newApp.deletingLastPathComponent())
                let alert = NSAlert()
                alert.messageText = "请手动完成更新"
                alert.informativeText = "新版已下载并打开所在文件夹。请退出 Aura，将新版拖入应用程序文件夹覆盖旧版。"
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
            return false
        }

        // 可写位置：备份旧版 → 替换 → 重启
        let backup = bundle.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.moveItem(at: bundle, to: backup)
        do {
            try FileManager.default.copyItem(at: newApp, to: bundle)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: bundle)
            throw error
        }
        try? FileManager.default.removeItem(at: backup)

        // 重新打开
        await MainActor.run {
            NSWorkspace.shared.open(bundle)
            NSApp.terminate(nil)
        }
        return true
    }
}
