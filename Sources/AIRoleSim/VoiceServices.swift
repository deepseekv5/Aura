import Foundation
import Speech
import AVFoundation
import AVFAudio
import Contacts
import AppKit
import CryptoKit

// MARK: - Mac 原生语音听写（Speech 框架，中文优先）

@MainActor
final class SpeechDictationService: NSObject, ObservableObject {
    static let shared = SpeechDictationService()

    @Published var isListening = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        guard !isListening else { return }
        errorMessage = nil

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] micGranted in
            guard let self else { return }
            guard micGranted else {
                DispatchQueue.main.async {
                    self.errorMessage = "麦克风权限未授权：请在 系统设置 → 隐私与安全性 → 麦克风 中允许 Aura"
                }
                return
            }
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard status == .authorized else {
                        self.errorMessage = "语音识别权限未授权：请在 系统设置 → 隐私与安全性 → 语音识别 中允许 Aura"
                        return
                    }
                    self.beginListening()
                }
            }
        }
    }

    private func beginListening() {
        let locale = Locale(identifier: "zh-CN")
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "语音识别当前不可用"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = false
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()

        transcript = ""
        isListening = true
        do {
            try audioEngine.start()
        } catch {
            isListening = false
            errorMessage = "无法启动麦克风：\(error.localizedDescription)"
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.finishListening()
                }
            }
        }
    }

    private func finishListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }

    func stop() {
        finishListening()
    }
}

// MARK: - 打电话（通讯录查找 + 系统拨号，经 iPhone 接续）

struct CallArgs: Codable {
    var target: String
}

enum CallService {

    struct Result: Codable {
        var status: String
        var target: String
        var number: String?
        var detail: String?
    }

    static func json(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"error\"}"
    }

    /// 纯数字 → 直接拨打；否则按通讯录联系人姓名查找
    static func call(target: String) async -> String {
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return json(Result(status: "error", target: target, detail: "通话对象为空")) }

        var number = ""
        if t.range(of: "^\\+?[0-9\\-\\s]{5,}$", options: .regularExpression) != nil {
            number = t.replacingOccurrences(of: " ", with: "")
        } else {
            // 通讯录查找
            let store = CNContactStore()
            let granted: Bool
            if #available(macOS 13.0, *) {
                granted = (try? await store.requestAccess(for: .contacts)) ?? false
            } else {
                granted = await withCheckedContinuation { cont in
                    store.requestAccess(for: .contacts) { ok, _ in cont.resume(returning: ok) }
                }
            }
            guard granted else {
                return json(Result(status: "denied", target: target, detail: "通讯录权限未授权，无法按姓名查找；可直接说电话号码"))
            }
            let keys = [CNContactPhoneNumbersKey, CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
            let predicate = CNContact.predicateForContacts(matchingName: t)
            let results = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
            guard let contact = results.first, let phone = contact.phoneNumbers.first?.value.stringValue else {
                return json(Result(status: "not_found", target: target, detail: "通讯录中未找到联系人「\(t)」"))
            }
            number = phone
        }

        let telURL = URL(string: "tel://\(number.replacingOccurrences(of: "-", with: ""))")
        guard let telURL else { return json(Result(status: "error", target: target, detail: "号码无效")) }
        let ok = await MainActor.run { NSWorkspace.shared.open(telURL) }
        return ok
            ? json(Result(
                status: "dialing",
                target: target,
                number: number,
                detail: "已发起拨号，系统将通过 iPhone 接续完成通话，请在弹出的确认框中确认"
            ))
            : json(Result(status: "error", target: target, detail: "系统未能发起拨号"))
    }
}

// MARK: - 屏幕读取密码（CryptoKit SHA256 + 盐）

enum PasswordStore {
    static func hash(_ password: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + password).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func makeSalt() -> String {
        UUID().uuidString
    }
}
