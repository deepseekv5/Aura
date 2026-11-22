import Foundation

// MARK: - iCloud 备份（CloudKit Ubiquity 容器，纯文件方式，无服务器）
// 将 Aura 的完整数据备份 JSON 存入 iCloud Drive 的隐藏目录 ~/Library/Mobile Documents/iCloud~com~aura~backup/Documents/
// 用户须在系统设置中登录 iCloud 并开启 iCloud Drive。

enum CloudBackupService {

    struct BackupInfo: Codable {
        var date: Date
        var version: Int
        var characters: Int
        var conversations: Int
        var memories: Int
        var byteSize: Int
    }

    static let folderName = "AuraBackups"
    static let infoName = "latest.json"

    /// iCloud 是否可用（登录 + iCloud Drive 开启）
    static func isAvailable() -> Bool {
        guard let url = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return false }
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    private static func backupDir() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw APIError.decoding("iCloud 不可用：请先在系统设置中登录 iCloud 并开启 iCloud Drive")
        }
        let dir = container.appendingPathComponent("Documents").appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 备份数据到 iCloud
    @discardableResult
    static func backup(data: Data, info: BackupInfo) throws -> URL {
        let dir = try backupDir()
        let dataURL = dir.appendingPathComponent("aura-backup.json")
        let infoURL = dir.appendingPathComponent(infoName)
        try data.write(to: dataURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(info).write(to: infoURL, options: .atomic)
        return dataURL
    }

    /// 从 iCloud 恢复数据
    static func restore() throws -> (data: Data, info: BackupInfo) {
        let dir = try backupDir()
        let dataURL = dir.appendingPathComponent("aura-backup.json")
        let infoURL = dir.appendingPathComponent(infoName)
        guard let data = try? Data(contentsOf: dataURL),
              let infoData = try? Data(contentsOf: infoURL) else {
            throw APIError.decoding("iCloud 中没有找到备份")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let info = try decoder.decode(BackupInfo.self, from: infoData)
        return (data, info)
    }

    /// 读取备份元信息（不下载数据）
    static func latestInfo() -> BackupInfo? {
        guard let dir = try? backupDir(),
              let data = try? Data(contentsOf: dir.appendingPathComponent(infoName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BackupInfo.self, from: data)
    }

    /// 删除 iCloud 备份
    static func deleteBackup() throws {
        let dir = try backupDir()
        for name in ["aura-backup.json", infoName] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
