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
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.2"
    }

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
        guard isNewer(release.tag_name, than: currentVersion) else { return nil }

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

    private static func versionTuple(_ s: String) -> [Int] {
        s.replacingOccurrences(of: "v", with: "")
            .split(separator: ".")
            .map { Int($0.trimmingCharacters(in: .letters)) ?? 0 }
    }

    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let a = versionTuple(remote), b = versionTuple(local)
        for i in 0..<max(a.count, b.count) {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }

    /// 下载更新（校验所有重定向目标主机，仅 HTTPS + GitHub 白名单）
    /// 返回解压后的 .app 路径
    static func download(_ info: UpdateInfo, progress: @escaping (Double) -> Void) async throws -> URL {
        // 主机白名单：下载起点与所有重定向目标必须是 GitHub 官方域名
        let allowedHosts: Set<String> = [
            "github.com", "www.github.com", "objects.githubusercontent.com",
            "release-assets.githubusercontent.com", "github-releases.githubusercontent.com"
        ]

        func validate(_ url: URL) throws {
            guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
                throw APIError.invalidURL("更新地址必须使用 HTTPS：\(url.absoluteString)")
            }
            guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
                throw APIError.invalidURL("更新地址主机不在白名单：\(url.host ?? "未知")")
            }
        }

        try validate(info.downloadURL)

        let delegate = RedirectGuard(validate: validate)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, resp) = try await session.data(for: URLRequest(url: info.downloadURL))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "下载失败")
        }
        guard data.count > 100_000 else {
            throw APIError.decoding("下载文件过小，可能不是有效的安装包")
        }
        progress(1.0)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let zip = tmp.appendingPathComponent("update.zip")
        try data.write(to: zip)

        // ditto 解压（保留 macOS 资源分支与隔离属性）
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, tmp.path]
        let errPipe = Pipe()
        p.standardError = errPipe
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw APIError.decoding("解压失败：\(msg)")
        }

        // 递归查找 .app（zip 内可能多一层目录）
        func findApp(in dir: URL, depth: Int) -> URL? {
            guard depth < 3 else { return nil }
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
            for sub in items where sub.hasDirectoryPath {
                if let found = findApp(in: sub, depth: depth + 1) { return found }
            }
            return nil
        }
        guard let app = findApp(in: tmp, depth: 0) else {
            throw APIError.decoding("安装包中没有找到 .app")
        }
        return app
    }

    /// 安装更新（不自动替换应用，改为打开新版所在文件夹让用户手动拖入，最安全）
    @discardableResult
    static func install(newApp: URL) async throws -> Bool {
        await MainActor.run {
            // 在新版所在文件夹里选中它
            NSWorkspace.shared.activateFileViewerSelecting([newApp])
        }
        return false // 未自动安装
    }
}

/// 重定向守卫：每一跳都校验 URL（HTTPS + 主机白名单）
private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    let validate: (URL) throws -> Void

    init(validate: @escaping (URL) throws -> Void) {
        self.validate = validate
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, (try? validate(url)) != nil else {
            completionHandler(nil) // 拒绝非法重定向
            return
        }
        completionHandler(request)
    }
}
