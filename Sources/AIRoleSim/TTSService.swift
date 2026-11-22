import Foundation
import AVFoundation

// MARK: - MiMo TTS（小米 MiMo，OpenAI 兼容接口，默认免费 mimo-v2.5-tts）

enum TTSService {

    static let endpoint = "https://api.xiaomimimo.com/v1/chat/completions"

    static let voices: [(id: String, label: String)] = [
        ("mimo_default", "默认音色"),
        ("冰糖", "冰糖"),
        ("茉莉", "茉莉"),
        ("苏打", "苏打"),
        ("白桦", "白桦"),
        ("Mia", "Mia"),
        ("Chloe", "Chloe"),
        ("Milo", "Milo"),
        ("Dean", "Dean")
    ]

    struct TTSRequest: Encodable {
        struct Msg: Encodable {
            var role: String
            var content: String
        }
        struct Audio: Encodable {
            var format: String
            var voice: String?
        }
        var model: String
        var messages: [Msg]
        var audio: Audio
        var stream: Bool = false
    }

    struct TTSResponse: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable {
                struct AudioData: Decodable {
                    var data: String?
                    var transcript: String?
                }
                var role: String?
                var audio: AudioData?
            }
            var message: Msg?
        }
        var choices: [Choice]?
        var error: ChatCompletionChunk.APIErrorBody?
    }

    static func synthesize(text: String, settings: AppSettings) async throws -> Data {
        // 固定官方地址：仅允许 HTTPS 且 host 必须为 api.xiaomimimo.com
        guard let url = URL(string: endpoint),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "api.xiaomimimo.com" else {
            throw APIError.invalidURL(endpoint)
        }
        guard !settings.ttsAPIKey.isEmpty else { throw APIError.notConfigured }

        // 长文本截断，避免超出合成限制
        let target = String(text.prefix(800))

        var msgs: [TTSRequest.Msg] = []
        if settings.ttsModel == "mimo-v2.5-tts-voicedesign" {
            // voicedesign 模型：user 消息为音色设计描述（必填）
            let desc = settings.ttsVoiceDesign.isEmpty ? "自然、亲切、清晰的叙述语气" : settings.ttsVoiceDesign
            msgs.append(TTSRequest.Msg(role: "user", content: desc))
        }
        // 指定合成文本的 assistant 消息
        msgs.append(TTSRequest.Msg(role: "assistant", content: target))

        let voice: String? = settings.ttsModel == "mimo-v2.5-tts-voicedesign" ? nil : settings.ttsVoice
        let body = TTSRequest(
            model: settings.ttsModel,
            messages: msgs,
            audio: TTSRequest.Audio(format: settings.ttsFormat.isEmpty ? "mp3" : settings.ttsFormat, voice: voice)
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(settings.ttsAPIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await APIClient.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.decoding("非 HTTP 响应") }
        guard http.statusCode < 400 else {
            throw APIError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(TTSResponse.self, from: data)
        if let e = decoded.error {
            throw APIError.http(200, e.message ?? "TTS 服务返回错误")
        }
        guard let b64 = decoded.choices?.first?.message?.audio?.data,
              !b64.isEmpty,
              let audio = Data(base64Encoded: b64), !audio.isEmpty else {
            throw APIError.decoding("TTS 未返回音频数据")
        }
        return audio
    }
}

// MARK: - 播放管理（自动朗读 / 手动播放 / 演示模式系统语音）

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()

    @Published var playingMessageID: UUID?
    @Published var lastError: String?

    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var cache: [UUID: Data] = [:]
    private var speakingMessageID: UUID?

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 播放/停止切换
    func toggle(message: ChatMessage, settings: AppSettings) async {
        let id = message.id
        if playingMessageID == id || speakingMessageID == id {
            stop()
            return
        }
        stop()
        guard !message.content.isEmpty else { return }

        playingMessageID = id
        lastError = nil
        do {
            if settings.demoMode {
                // 演示模式：系统语音兜底，真实可听
                speakSystem(text: message.content, id: id, rate: settings.speechRate)
                return
            }
            guard !settings.ttsAPIKey.isEmpty else {
                lastError = "未配置 MiMo API Key"
                playingMessageID = nil
                return
            }
            let data: Data
            if let c = cache[id] {
                data = c
            } else {
                data = try await TTSService.synthesize(text: message.content, settings: settings)
                cache[id] = data
            }
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            playingMessageID = nil
            lastError = error.localizedDescription
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingMessageID = nil
        playingMessageID = nil
    }

    /// 设置页试听
    func playDataForTest(data: Data) {
        stop()
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func speakSystem(text: String, id: UUID, rate: Double) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = Float(rate)
        speakingMessageID = id
        synthesizer.speak(u)
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playingMessageID = nil
        }
    }
}

extension AudioPlayerManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingMessageID = nil
            self.playingMessageID = nil
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingMessageID = nil
            self.playingMessageID = nil
        }
    }
}
