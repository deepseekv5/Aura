import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    @State private var connStates: [UUID: String] = [:]
    @State private var fetchedModels: [UUID: [String]] = [:]

    var body: some View {
        TabView {
            apiTab
                .tabItem { Label("API 配置", systemImage: "network") }
            ttsTab
                .tabItem { Label("语音朗读", systemImage: "speaker.wave.2") }
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 580, height: 560)
    }

    // MARK: API 配置

    private var apiTab: some View {
        Form {
            Section {
                Text("使用任意 OpenAI 兼容服务（OpenAI、DeepSeek、智谱、Kimi、OpenRouter、各类中转站）。Base URL 填根地址即可，会自动补全 /v1。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            ForEach($store.settings.profiles) { $profile in
                Section {
                    TextField("配置名称", text: $profile.name)
                    TextField("Base URL（如 https://api.deepseek.com）", text: $profile.baseURL)
                    SecureField("API Key", text: $profile.apiKey)

                    HStack {
                        TextField("模型名", text: $profile.model)
                            .textFieldStyle(.plain)
                        if let models = fetchedModels[profile.id], !models.isEmpty {
                            Menu("选择") {
                                ForEach(models, id: \.self) { m in
                                    Button(m) { profile.model = m }
                                }
                            }
                            .fixedSize()
                        }
                        Button {
                            fetchModels(profile)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .disabled(profile.baseURL.isEmpty)
                        .help("拉取模型列表")
                    }

                    LabeledContent("温度") {
                        HStack {
                            Slider(value: $profile.temperature, in: 0...2, step: 0.1)
                            Text(String(format: "%.1f", profile.temperature))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                        }
                    }
                    Stepper("最大回复 tokens：\(profile.maxTokens)", value: $profile.maxTokens, in: 1024...32768, step: 512)
                    Toggle("关闭思考模式", isOn: $profile.disableThinking)
                    if profile.disableThinking {
                        Text("适合 GLM 等会输出思考内容的推理模型：请求时附加 thinking=disabled，避免回复混入思考过程。其他服务若报参数错误请关闭。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }

                    HStack {
                        Button("测试连接") { test(profile) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        if !profile.isDefault {
                            Button("设为默认") { store.setDefaultProfile(profile.id) }
                                .controlSize(.small)
                        } else {
                            Text("默认配置")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button("删除", role: .destructive) {
                            store.settings.profiles.removeAll { $0.id == profile.id }
                            if store.settings.activeProfileID == profile.id { store.settings.activeProfileID = nil }
                        }
                        .controlSize(.small)
                        .disabled(store.settings.profiles.count <= 1)
                    }

                    if let state = connStates[profile.id] {
                        Text(state)
                            .font(.system(size: 11))
                            .foregroundStyle(state.hasPrefix("连接成功") ? .green : .orange)
                            .lineLimit(3)
                    }
                } header: {
                    Text(profile.name.isEmpty ? "配置" : profile.name)
                        .font(.system(size: 12, weight: .semibold))
                }
            }

            Section {
                Button("添加配置") {
                    store.settings.profiles.append(APIProfile(name: "配置 \(store.settings.profiles.count + 1)"))
                }
            }

            Section {
                Text("示例 Base URL：https://api.deepseek.com ｜ https://api.moonshot.cn ｜ https://open.bigmodel.cn/api/paas ｜ https://api.openai.com")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }

    // MARK: 语音朗读（MiMo TTS）

    @State private var ttsTestStatus: String?
    @State private var showPasswordSheet = false
    @State private var pendingScreenToggle: Bool?
    @State private var resettingPassword = false

    private var ttsTab: some View {
        Form {
            Section {
                Text("由小米 MiMo 开放平台提供语音合成（OpenAI 兼容），默认使用免费的 mimo-v2.5-tts。在 api.xiaomimimo.com 获取 API Key。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Toggle("自动朗读 AI 回复", isOn: $store.settings.ttsAuto)
                if store.settings.ttsAuto {
                    Text("每条回复生成后自动朗读，也可点击气泡下方的小喇叭手动播放。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Section("连接") {
                SecureField("MiMo API Key", text: $store.settings.ttsAPIKey)
                Picker("模型", selection: $store.settings.ttsModel) {
                    Text("mimo-v2.5-tts（免费）").tag("mimo-v2.5-tts")
                    Text("mimo-v2.5-tts-voicedesign").tag("mimo-v2.5-tts-voicedesign")
                }
                if store.settings.ttsModel == "mimo-v2.5-tts-voicedesign" {
                    TextField("音色设计描述（如何发声）", text: $store.settings.ttsVoiceDesign)
                } else {
                    Picker("音色", selection: $store.settings.ttsVoice) {
                        ForEach(TTSService.voices, id: \.id) { v in
                            Text(v.label).tag(v.id)
                        }
                    }
                }
                Picker("音频格式", selection: $store.settings.ttsFormat) {
                    Text("mp3").tag("mp3")
                    Text("wav").tag("wav")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                HStack {
                    Button("试听") { testTTS() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(store.settings.ttsAPIKey.isEmpty)
                    if let s = ttsTestStatus {
                        Text(s)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Section {
                Text("演示模式下不调用 MiMo，改用 macOS 系统语音朗读。语音仅供本地播放，不会保存音频文件。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }

    @State private var dataStatus: String?
    @State private var showUpdateView = false

    private func exportData() {
        guard let data = store.exportAllData() else { dataStatus = "导出失败"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Aura-backup-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).json"
        panel.begin { r in
            guard r == .OK, let url = panel.url else { return }
            try? data.write(to: url)
            dataStatus = "已导出"
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { r in
            guard r == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            dataStatus = store.importAllData(data) ? "导入成功" : "格式无效"
        }
    }

    // MARK: 屏幕读取密码

    private var passwordSheet: some View {
        PasswordSheet(
            mode: resettingPassword ? .reset : (store.settings.screenPasswordHash.isEmpty ? .setup : .unlock),
            store: store,
            pendingEnable: pendingScreenToggle
        ) {
            showPasswordSheet = false
            pendingScreenToggle = nil
            resettingPassword = false
        }
    }

    private func testTTS() {
        ttsTestStatus = "正在合成…"
        Task {
            do {
                let data = try await TTSService.synthesize(text: "你好，我是你的专属角色，很高兴见到你。", settings: store.settings)
                await AudioPlayerManager.shared.playDataForTest(data: data)
                ttsTestStatus = "已播放"
            } catch {
                ttsTestStatus = "失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: 通用

    private var generalTab: some View {
        Form {
            Section {
                Toggle("演示模式（无需 API Key，本地模拟对话与记忆写入）", isOn: $store.settings.demoMode)
                if store.settings.demoMode {
                    Text("演示模式下所有回复由本地生成，仅用于体验界面与记忆链路。")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Section("用户身份（让角色知道你是谁）") {
                TextField("你的昵称", text: $store.settings.userName)
                LabeledTextEditor(label: "自我介绍（可选）", text: $store.settings.userBio, minHeight: 50, placeholder: "职业、兴趣、希望角色如何称呼你……")
            }

            Section("屏幕读取（密码保护）") {
                Toggle("允许角色读取屏幕", isOn: Binding(
                    get: { store.settings.screenEnabled },
                    set: { on in
                        if on {
                            // 开启：必须通过密码（未设置则先设置）
                            pendingScreenToggle = on
                            showPasswordSheet = true
                        } else {
                            store.settings.screenEnabled = false
                            store.screenUnlocked = false
                        }
                    }
                ))
                if store.settings.screenEnabled {
                    Picker("读取范围", selection: $store.settings.screenMode) {
                        Text("整个屏幕").tag("full")
                        Text("最前面的窗口").tag("window")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    if store.screenUnlocked {
                        Text("已解锁，本次运行期间可正常读取屏幕。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.green)
                    } else if store.settings.screenPasswordHash.isEmpty {
                        Text("尚未设置密码，请点击下方「设置密码」。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                    } else {
                        Text("已锁定。点击下方「解锁」输入密码后，本次运行期间生效。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Button(store.settings.screenPasswordHash.isEmpty ? "设置密码" : "解锁") {
                            pendingScreenToggle = nil
                            showPasswordSheet = true
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        if store.settings.screenPasswordHash.isEmpty == false {
                            Button("重设密码") {
                                resettingPassword = true
                                showPasswordSheet = true
                            }
                            .controlSize(.small)
                        }
                    }
                    Text("开启后，你说「看看我的屏幕」或「截屏」时，角色会截取屏幕（\(store.settings.screenMode == "full" ? "整个屏幕" : "最前面的窗口")）并用支持视觉的模型解读。首次使用需在 系统设置 → 隐私与安全性 → 屏幕录制 中授权。密码用于保护屏幕隐私，重启后需重新解锁。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }

            Section("表达与记忆") {
                Toggle("全局避免角色回复 emoji（角色可单独覆盖）", isOn: $store.settings.noEmojiReplies)
                Stepper("每轮注入记忆条数：\(store.settings.memoryTopK)", value: $store.settings.memoryTopK, in: 4...16)
                Picker("强调色", selection: $store.settings.accentColorHex) {
                    Text("系统默认").tag("")
                    ForEach(Palette.swatches, id: \.self) { hex in
                        HStack {
                            Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                            Text(hex).font(.system(size: 11))
                        }.tag(hex)
                    }
                }
                LabeledContent("朗读语速") {
                    Slider(value: $store.settings.speechRate, in: 0.3...1.0, step: 0.05)
                    Text(String(format: "%.2f", store.settings.speechRate))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 34)
                }
            }

            Section("软件更新") {
                HStack {
                    Text("当前版本 v\(UpdateService.currentVersion)")
                        .font(.system(size: 12))
                    Spacer()
                    Button("检查更新") { showUpdateView = true }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                Toggle("启动时自动检查更新", isOn: $store.settings.autoCheckUpdates)
                    .font(.system(size: 12))
            }

            Section("数据") {
                LabeledContent("存储位置") {
                    Button("在访达中打开") { store.openDataFolder() }
                        .controlSize(.small)
                }
                Text(store.dataDir.path)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack {
                    Button("导出全部数据") { exportData() }
                        .controlSize(.small)
                    Button("导入数据") { importData() }
                        .controlSize(.small)
                    if let s = dataStatus {
                        Text(s).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
        .sheet(isPresented: $showPasswordSheet) {
            passwordSheet
        }
    }

    // MARK: 动作

    private func fetchModels(_ profile: APIProfile) {
        connStates[profile.id] = "正在拉取模型列表…"
        Task {
            do {
                let models = try await APIClient.listModels(profile: profile)
                fetchedModels[profile.id] = models
                connStates[profile.id] = "已获取 \(models.count) 个模型"
            } catch {
                connStates[profile.id] = "拉取失败：\(error.localizedDescription)"
            }
        }
    }

    private func test(_ profile: APIProfile) {
        connStates[profile.id] = "测试中…"
        Task {
            do {
                let msg = try await APIClient.testConnection(profile: profile)
                connStates[profile.id] = msg
            } catch {
                connStates[profile.id] = "失败：\(error.localizedDescription)"
            }
        }
    }
}
