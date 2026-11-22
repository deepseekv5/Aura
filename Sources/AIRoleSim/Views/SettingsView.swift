import SwiftUI

// MARK: - 现代设置页：侧栏导航 + 顶部搜索 + 卡片式内容
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    enum SectionID: String, CaseIterable, Identifiable {
        case api = "API 配置"
        case voice = "语音朗读"
        case general = "通用"
        case privacy = "隐私与安全"
        case data = "数据与备份"
        case about = "关于与法律"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .api: return "network"
            case .voice: return "speaker.wave.2"
            case .general: return "gearshape"
            case .privacy: return "hand.raised.shield"
            case .data: return "externaldrive.backup"
            case .about: return "book.closed"
            }
        }
        var keywords: String {
            switch self {
            case .api: return "api 模型 密钥 url 地址 配置 中转 deepseek openai 混元 测试 温度"
            case .voice: return "语音 朗读 tts mimo 音色 听写 语速 麦克风"
            case .general: return "通用 演示 昵称 用户 emoji 记忆 强调色 主题 更新"
            case .privacy: return "隐私 屏幕 密码 锁定 权限 协议 同意"
            case .data: return "数据 备份 导出 导入 icloud 云 自动"
            case .about: return "关于 协议 条款 隐私政策 版本 法律"
            }
        }
    }

    @State private var selection: SectionID = .api
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var filteredSections: [SectionID] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return SectionID.allCases }
        return SectionID.allCases.filter {
            $0.rawValue.lowercased().contains(q) || $0.keywords.contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 620)
        .onAppear { searchFocused = false }
    }

    // MARK: 侧栏
    private var sidebar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("搜索设置…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.horizontal, 12)

            List(filteredSections, selection: $selection) { sec in
                Label(sec.rawValue, systemImage: sec.icon)
                    .font(.system(size: 13))
                    .tag(sec)
            }
            .listStyle(.sidebar)
            .frame(maxHeight: .infinity)

            VStack(spacing: 4) {
                Text("Aura v\(UpdateService.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                Text("所有数据仅存于本地")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
            .padding(.bottom, 14)
        }
        .frame(width: 210)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .api: APISettingsPane()
        case .voice: VoiceSettingsPane()
        case .general: GeneralSettingsPane()
        case .privacy: PrivacySettingsPane()
        case .data: DataSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}

// MARK: - 通用设置面板（内部共享状态）
struct APISettingsPane: View {
    @EnvironmentObject var store: AppStore
    @State private var connStates: [UUID: String] = [:]
    @State private var fetchedModels: [UUID: [String]] = [:]

    var body: some View {
        SettingsPane(title: "API 配置", subtitle: "连接你自己的 AI 服务") {
            SettingsCard {
                Text("使用任意 OpenAI 兼容服务。Base URL 填根地址即可，自动补全 /v1。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            ForEach($store.settings.profiles) { $profile in
                SettingsCard(title: profile.name.isEmpty ? "配置" : profile.name) {
                    LabeledContent("名称") { TextField("", text: $profile.name).textFieldStyle(.roundedBorder).frame(width: 220) }
                    LabeledContent("Base URL") { TextField("https://api.deepseek.com", text: $profile.baseURL).textFieldStyle(.roundedBorder).frame(width: 300) }
                    LabeledContent("API Key") { SecureField("sk-…", text: $profile.apiKey).textFieldStyle(.roundedBorder).frame(width: 300) }
                    LabeledContent("模型") {
                        HStack {
                            TextField("model", text: $profile.model).textFieldStyle(.roundedBorder).frame(width: 180)
                            if let models = fetchedModels[profile.id] {
                                Menu("选择") {
                                    ForEach(models, id: \.self) { m in Button(m) { profile.model = m } }
                                }
                            }
                            Button { fetchModels(profile) } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("拉取模型列表")
                            .disabled(profile.baseURL.isEmpty)
                        }
                    }
                    LabeledContent("温度") {
                        HStack {
                            Slider(value: $profile.temperature, in: 0...2, step: 0.1).frame(width: 160)
                            Text(String(format: "%.1f", profile.temperature)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("最大 tokens") {
                        Stepper("\(profile.maxTokens)", value: $profile.maxTokens, in: 1024...32768, step: 512)
                            .frame(width: 150)
                    }
                    Toggle("关闭思考模式（GLM 等推理模型）", isOn: $profile.disableThinking)
                        .font(.system(size: 12))

                    HStack {
                        Button("测试连接") { test(profile) }.buttonStyle(.glass).controlSize(.small)
                        if !profile.isDefault {
                            Button("设为默认") { store.setDefaultProfile(profile.id) }.controlSize(.small)
                        } else {
                            Label("默认配置", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(.green)
                        }
                        Spacer()
                        Button("删除", role: .destructive) {
                            store.settings.profiles.removeAll { $0.id == profile.id }
                        }
                        .controlSize(.small)
                        .disabled(store.settings.profiles.count <= 1)
                    }
                    if let state = connStates[profile.id] {
                        Text(state).font(.system(size: 10.5))
                            .foregroundStyle(state.hasPrefix("连接成功") ? .green : .orange)
                    }
                }
            }

            SettingsCard {
                HStack {
                    Button("添加配置") {
                        store.settings.profiles.append(APIProfile(name: "配置 \(store.settings.profiles.count + 1)"))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    Spacer()
                }
            }
        }
    }

    private func fetchModels(_ p: APIProfile) {
        connStates[p.id] = "拉取中…"
        Task {
            do {
                let models = try await APIClient.listModels(profile: p)
                fetchedModels[p.id] = models
                connStates[p.id] = "已获取 \(models.count) 个模型"
            } catch { connStates[p.id] = "失败：\(error.localizedDescription)" }
        }
    }

    private func test(_ p: APIProfile) {
        connStates[p.id] = "测试中…"
        Task {
            do { connStates[p.id] = try await APIClient.testConnection(profile: p) }
            catch { connStates[p.id] = "失败：\(error.localizedDescription)" }
        }
    }
}

struct VoiceSettingsPane: View {
    @EnvironmentObject var store: AppStore
    @State private var testStatus: String?

    var body: some View {
        SettingsPane(title: "语音朗读", subtitle: "MiMo TTS · 系统听写") {
            SettingsCard {
                Toggle("自动朗读 AI 回复", isOn: $store.settings.ttsAuto)
                Text("每条回复生成后自动朗读，也可点击气泡下方小喇叭手动播放。")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            SettingsCard(title: "MiMo TTS 连接") {
                SecureField("MiMo API Key", text: $store.settings.ttsAPIKey)
                    .textFieldStyle(.roundedBorder)
                Picker("模型", selection: $store.settings.ttsModel) {
                    Text("mimo-v2.5-tts（免费）").tag("mimo-v2.5-tts")
                    Text("mimo-v2.5-tts-voicedesign").tag("mimo-v2.5-tts-voicedesign")
                }
                if store.settings.ttsModel == "mimo-v2.5-tts-voicedesign" {
                    TextField("音色设计描述", text: $store.settings.ttsVoiceDesign)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("音色", selection: $store.settings.ttsVoice) {
                        ForEach(TTSService.voices, id: \.id) { Text($0.label).tag($0.id) }
                    }
                }
                Picker("格式", selection: $store.settings.ttsFormat) {
                    Text("mp3").tag("mp3"); Text("wav").tag("wav")
                }.pickerStyle(.segmented).frame(width: 150)
                HStack {
                    Button("试听") {
                        testStatus = "合成中…"
                        Task {
                            do {
                                let data = try await TTSService.synthesize(text: "你好，我是 Aura。", settings: store.settings)
                                await AudioPlayerManager.shared.playDataForTest(data: data)
                                testStatus = "已播放"
                            } catch { testStatus = "失败：\(error.localizedDescription)" }
                        }
                    }
                    .buttonStyle(.glass).controlSize(.small)
                    .disabled(store.settings.ttsAPIKey.isEmpty)
                    if let s = testStatus {
                        Text(s).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsCard(title: "语音输入与语速") {
                LabeledContent("朗读语速") {
                    HStack {
                        Slider(value: $store.settings.speechRate, in: 0.3...1.0, step: 0.05).frame(width: 180)
                        Text(String(format: "%.2f", store.settings.speechRate)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Text("输入条左侧麦克风按钮使用 macOS 原生语音识别听写，首次使用需授权麦克风与语音识别权限。")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct GeneralSettingsPane: View {
    @EnvironmentObject var store: AppStore
    @State private var showUpdate = false
    @State private var updateStatus: String?

    private var stats: AppStore.UsageStats { store.usageStats() }

    var body: some View {
        SettingsPane(title: "通用", subtitle: "基础体验与偏好") {
            SettingsCard {
                Toggle("演示模式（无需 API Key，本地模拟）", isOn: $store.settings.demoMode)
                if store.settings.demoMode {
                    Text("演示模式回复由本地生成，仅用于体验界面与记忆链路。")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            SettingsCard(title: "使用统计") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(value: "\(stats.totalMessages)", label: "消息总数", icon: "bubble.left.and.bubble.right")
                    StatTile(value: "\(stats.totalMemories)", label: "长期记忆", icon: "brain")
                    StatTile(value: "\(stats.daysSinceFirstUse)", label: "使用天数", icon: "calendar")
                }
            }
            SettingsCard(title: "用户身份") {
                TextField("你的昵称", text: $store.settings.userName)
                    .textFieldStyle(.roundedBorder)
                LabeledTextEditor(label: "自我介绍", text: $store.settings.userBio, minHeight: 60, placeholder: "职业、兴趣、希望角色如何称呼你……")
            }
            SettingsCard(title: "外观与表达") {
                Picker("强调色", selection: $store.settings.accentColorHex) {
                    Text("系统默认").tag("")
                    ForEach(Palette.swatches, id: \.self) { hex in
                        HStack {
                            Circle().fill(Color(hex: hex)).frame(width: 12, height: 12)
                            Text(hex).font(.system(size: 11))
                        }.tag(hex)
                    }
                }
                Toggle("回复避免 emoji", isOn: $store.settings.noEmojiReplies)
                Stepper("每轮注入记忆：\(store.settings.memoryTopK) 条", value: $store.settings.memoryTopK, in: 4...16)
            }
            SettingsCard(title: "软件更新") {
                HStack {
                    Text("当前 v\(UpdateService.currentVersion)").font(.system(size: 12))
                    Spacer()
                    Button("检查更新") {
                        showUpdate = true
                    }
                    .buttonStyle(.glass).controlSize(.small)
                }
                Toggle("启动时自动检查更新", isOn: $store.settings.autoCheckUpdates)
                    .font(.system(size: 12))
                if let s = updateStatus {
                    Text(s).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showUpdate) { UpdateView() }
        }
    }
}

struct PrivacySettingsPane: View {
    @EnvironmentObject var store: AppStore
    @State private var showPassword = false
    @State private var resetting = false
    @State private var showLegal = false
    @State private var legalMode: LegalDocumentsView.Mode = .terms

    var body: some View {
        SettingsPane(title: "隐私与安全", subtitle: "掌控你的数据与权限") {
            SettingsCard(title: "数据本地化") {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("所有数据仅存于你的设备")
                            .font(.system(size: 12, weight: .medium))
                        Text("Aura 没有服务器，不会主动上传你的对话、记忆或 API 密钥。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            SettingsCard(title: "屏幕读取（密码保护）") {
                Toggle("允许角色读取屏幕", isOn: Binding(
                    get: { store.settings.screenEnabled },
                    set: { on in
                        if on { resetting = false; showPassword = true }
                        else { store.settings.screenEnabled = false; store.screenUnlocked = false }
                    }
                ))
                if store.settings.screenEnabled {
                    Picker("读取范围", selection: $store.settings.screenMode) {
                        Text("整个屏幕").tag("full")
                        Text("最前面的窗口").tag("window")
                    }.pickerStyle(.segmented).frame(width: 220)
                    HStack {
                        Label(store.screenUnlocked ? "已解锁" : (store.settings.screenPasswordHash.isEmpty ? "未设置密码" : "已锁定"),
                              systemImage: store.screenUnlocked ? "checkmark.circle.fill" : "lock.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(store.screenUnlocked ? .green : .orange)
                        Spacer()
                        Button(store.settings.screenPasswordHash.isEmpty ? "设置密码" : (store.screenUnlocked ? "重设密码" : "解锁")) {
                            resetting = store.screenUnlocked
                            showPassword = true
                        }
                        .buttonStyle(.glass).controlSize(.small)
                    }
                }
            }
            SettingsCard(title: "法律条款（随时可查看）") {
                HStack {
                    Button { legalMode = .terms; showLegal = true } label: {
                        Label("用户服务协议", systemImage: "doc.text")
                    }.controlSize(.small)
                    Button { legalMode = .privacy; showLegal = true } label: {
                        Label("隐私政策", systemImage: "hand.raised")
                    }.controlSize(.small)
                    Spacer()
                    if !store.settings.legalConsentVersion.isEmpty {
                        Text("已同意 v\(store.settings.legalConsentVersion)")
                            .font(.system(size: 10)).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showLegal) {
                LegalDocumentsView(mode: legalMode)
            }
        }
        .sheet(isPresented: $showPassword) {
            PasswordSheet(
                mode: resetting ? .reset : (store.settings.screenPasswordHash.isEmpty ? .setup : .unlock),
                store: store,
                pendingEnable: nil
            ) { showPassword = false; resetting = false }
        }
    }
}

struct DataSettingsPane: View {
    @EnvironmentObject var store: AppStore
    @State private var dataStatus: String?
    @State private var cloudInfo: CloudBackupService.BackupInfo?
    @State private var cloudBusy = false

    var body: some View {
        SettingsPane(title: "数据与备份", subtitle: "导出、导入与 iCloud 同步") {
            SettingsCard(title: "快速导出 / 导入") {
                Text("将所有角色、对话、记忆与设置打包为一个 JSON 文件，可随时恢复。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { exportData() } label: {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button { importData() } label: {
                        Label("导入备份", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                if let s = dataStatus {
                    Text(s).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "自动本地备份") {
                Toggle("每次变更后自动备份（保留最近 3 份）", isOn: $store.settings.autoBackup)
                    .font(.system(size: 12))
                Text("备份目录：\(store.dataDir.appendingPathComponent("Backups").path)")
                    .font(.system(size: 9.5)).foregroundStyle(.quaternary)
                    .textSelection(.enabled)
                Button("立即备份一次") { store.autoLocalBackup(); dataStatus = "本地备份完成" }
                    .controlSize(.small)
            }

            SettingsCard(title: "iCloud 备份") {
                if CloudBackupService.isAvailable() {
                    Toggle("自动备份到 iCloud Drive", isOn: $store.settings.iCloudBackupEnabled)
                        .font(.system(size: 12))
                    HStack {
                        Button(cloudBusy ? "处理中…" : "备份到 iCloud") { cloudBackup() }
                            .buttonStyle(.glass).controlSize(.small).disabled(cloudBusy)
                        Button("从 iCloud 恢复") { cloudRestore() }
                            .controlSize(.small).disabled(cloudBusy)
                        Spacer()
                    }
                    if let info = cloudInfo {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("最近备份：\(info.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Text("\(info.characters) 角色 · \(info.conversations) 会话 · \(info.memories) 记忆 · \(info.byteSize / 1024) KB")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("尚无 iCloud 备份").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Text("备份保存在你的私人 iCloud Drive 中，Aura 无法通过服务器访问。")
                        .font(.system(size: 10)).foregroundStyle(.quaternary)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.slash").foregroundStyle(.secondary)
                        Text("iCloud 不可用：请在系统设置中登录 iCloud 并开启 iCloud Drive")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            SettingsCard(title: "存储位置") {
                HStack {
                    Text(store.dataDir.path)
                        .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    Spacer()
                    Button("在访达中打开") { store.openDataFolder() }.controlSize(.small)
                }
            }
        }
        .onAppear { cloudInfo = CloudBackupService.latestInfo() }
    }

    private func exportData() {
        guard let data = store.exportAllData() else { dataStatus = "导出失败"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Aura-backup-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).json"
        panel.message = "选择备份文件的保存位置（默认建议放在桌面或文稿）"
        panel.prompt = "导出"

        // 绑定到当前 keyWindow，避免在 sheet 弹窗中不显示
        let window = NSApp.keyWindow
        let done: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                dataStatus = "已导出：\(url.path)"
                // 在访达中显示导出位置
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                dataStatus = "写入失败：\(error.localizedDescription)"
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: done)
        } else {
            panel.begin(completionHandler: done)
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "选择 Aura 备份文件（Aura-backup-日期.json）"
        panel.prompt = "导入"

        let window = NSApp.keyWindow
        let done: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url) else {
                dataStatus = "无法读取：\(url.lastPathComponent)"
                return
            }
            dataStatus = store.importAllData(data)
                ? "导入成功，数据已恢复（来自 \(url.lastPathComponent)）"
                : "备份格式无效：\(url.lastPathComponent)"
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: done)
        } else {
            panel.begin(completionHandler: done)
        }
    }

    private func cloudBackup() {
        guard let data = store.exportAllData() else { return }
        let s = store.usageStats()
        let info = CloudBackupService.BackupInfo(
            date: Date(), version: 1,
            characters: store.characters.count,
            conversations: store.conversations.count,
            memories: s.totalMemories,
            byteSize: data.count
        )
        cloudBusy = true
        do {
            try CloudBackupService.backup(data: data, info: info)
            cloudInfo = info
            dataStatus = "已备份到 iCloud"
        } catch {
            dataStatus = "iCloud 备份失败：\(error.localizedDescription)"
        }
        cloudBusy = false
    }

    private func cloudRestore() {
        cloudBusy = true
        do {
            let result = try CloudBackupService.restore()
            dataStatus = store.importAllData(result.data) ? "已从 iCloud 恢复数据" : "备份格式无效"
            cloudInfo = result.info
        } catch {
            dataStatus = "iCloud 恢复失败：\(error.localizedDescription)"
        }
        cloudBusy = false
    }
}

struct AboutSettingsPane: View {
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        SettingsPane(title: "关于与法律", subtitle: "Aura · AI 角色工坊") {
            SettingsCard {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.accentColor)
                    Text("Aura").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("AI 角色工坊 · macOS 原生应用").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("v\(UpdateService.currentVersion)").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            SettingsCard(title: "法律文档") {
                HStack {
                    Button { showTerms = true } label: { Label("用户服务协议", systemImage: "doc.text") }
                        .controlSize(.small)
                    Button { showPrivacy = true } label: { Label("隐私政策", systemImage: "hand.raised") }
                        .controlSize(.small)
                    Spacer()
                }
            }
            SettingsCard(title: "开源") {
                HStack {
                    Text("github.com/deepseekv5/Aura").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("在浏览器打开") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/deepseekv5/Aura")!)
                    }.controlSize(.small)
                }
                Text("源代码采用 MIT 许可证。").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showTerms) { LegalDocumentsView(mode: .terms) }
        .sheet(isPresented: $showPrivacy) { LegalDocumentsView(mode: .privacy) }
    }
}

// MARK: - 共用 UI 组件

struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 20, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                content
            }
            .padding(22)
        }
    }
}

struct SettingsCard<Content: View>: View {
    var title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.accentColor)
            Text(value).font(.system(size: 18, weight: .semibold))
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
