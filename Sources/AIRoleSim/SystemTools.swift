import Foundation
import AppKit
import CoreGraphics

// MARK: - 屏幕读取（screencapture CLI；首次使用系统会请求屏幕录制权限）

struct ScreenArgs: Codable {
    var mode: String?   // full / window
}

enum ScreenService {

    struct Result: Codable {
        var status: String
        var mode: String
        var detail: String?
    }

    static func json(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"error\"}"
    }

    /// 返回 (图片数据, 工具结果 JSON)
    static func capture(mode rawMode: String?) async -> (Data?, String) {
        let mode = (rawMode == "window") ? "window" : "full"
        var args = ["-x", "-t", "jpg", "-m"]  // -m 主显示器
        if mode == "window", let wid = frontWindowID(excludingSelf: true) {
            args = ["-x", "-t", "jpg", "-l", "\(wid)"]
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = args + [tmp.path]
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return (nil, json(Result(status: "error", mode: mode, detail: error.localizedDescription)))
        }
        guard let data = try? Data(contentsOf: tmp), data.count > 1000 else {
            // 最常见原因：屏幕录制权限未授权
            return (nil, json(Result(
                status: "error",
                mode: mode,
                detail: "截屏失败——请在 系统设置 → 隐私与安全性 → 屏幕录制 中授权本应用，然后重试"
            )))
        }
        return (data, json(Result(status: "ok", mode: mode, detail: nil)))
    }

    /// 最前面的非本应用窗口
    private static func frontWindowID(excludingSelf: Bool) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int ?? -1) == 0 else { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if excludingSelf && (owner.contains("AIRoleSim") || owner.contains("AI 角色模拟")) { continue }
            if let n = w[kCGWindowNumber as String] as? Int, n > 0 {
                return CGWindowID(n)
            }
        }
        return nil
    }
}

// MARK: - 剪贴板读取

enum ClipboardService {
    struct Result: Codable {
        var type: String      // text / image / empty
        var content: String?
        var file: String?
    }

    static func json(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"type\":\"empty\"}"
    }

    static func read() async -> String {
        let pb = NSPasteboard.general
        if let s = pb.string(forType: .string), !s.isEmpty {
            let trimmed = String(s.prefix(2000))
            return json(Result(type: "text", content: trimmed, file: nil))
        }
        if pb.types?.contains(.png) == true || pb.types?.contains(.tiff) == true,
           let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            let name = ImageStore.save(jpg)
            return json(Result(type: "image", content: nil, file: name))
        }
        return json(Result(type: "empty", content: nil, file: nil))
    }
}

// MARK: - 打开网址

struct OpenURLArgs: Codable {
    var url: String
}

enum OpenURLService {
    struct Result: Codable {
        var status: String
        var url: String
        var detail: String?
    }

    static func open(_ raw: String) async -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else {
            return json(Result(status: "error", url: s, detail: "网址为空"))
        }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return json(Result(status: "error", url: s, detail: "仅支持 http/https 网址"))
        }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        return json(Result(status: ok ? "opened" : "error", url: s, detail: ok ? nil : "系统未能打开该网址"))
    }

    private static func json(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"error\"}"
    }
}

// MARK: - 系统状态

enum SystemInfoService {
    struct Result: Codable {
        var os: String
        var memory_gb: Double
        var disk_free_gb: Double
        var battery_percent: Int?
        var battery_charging: Bool?
        var uptime_hours: Double
    }

    static func info() -> String {
        let pi = ProcessInfo.processInfo
        let memoryGB = Double(pi.physicalMemory) / 1_073_741_824
        let uptimeH = pi.systemUptime / 3600

        let diskFree: Double = {
            if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
               let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let free = values.volumeAvailableCapacityForImportantUsage {
                return Double(free) / 1_073_741_824
            }
            return 0
        }()

        // 电量：pmset -g batt
        var batteryPercent: Int?
        var charging: Bool?
        if let out = runCommand("/usr/bin/pmset", ["-g", "batt"]) {
            if let r = out.range(of: "(\\d+)%", options: .regularExpression) {
                let s = out[r].dropLast(1)
                batteryPercent = Int(s)
            }
            charging = out.contains("AC Power") || out.contains("charging")
        }

        let r = Result(
            os: pi.operatingSystemVersionString,
            memory_gb: (memoryGB * 10).rounded() / 10,
            disk_free_gb: (diskFree * 10).rounded() / 10,
            battery_percent: batteryPercent,
            battery_charging: charging,
            uptime_hours: (uptimeH * 10).rounded() / 10
        )
        let json = (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"error\":\"获取失败\"}"
        return json
    }

    private static func runCommand(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
