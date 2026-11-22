import SwiftUI

// MARK: - 角色编辑器（创建 / 编辑）

struct CharacterEditorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let existing: RoleProfile?

    @State private var draft = RoleProfile()
    @State private var tagText = ""
    @State private var overrideTemp = false
    @State private var portraitBusy = false
    @State private var portraitStatus = ""
    @State private var portraitHint = ""

    private let templates: [CharacterTemplate] = CharacterTemplate.presets

    init(character: RoleProfile?) {
        self.existing = character
        if let c = character {
            _draft = State(initialValue: c)
            _tagText = State(initialValue: c.tags.joined(separator: ", "))
            _overrideTemp = State(initialValue: c.temperatureOverride != nil)
        } else {
            var d = RoleProfile()
            d.colorHex = Palette.random()
            _draft = State(initialValue: d)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if existing == nil {
                    Section("快速开始（可选，点选后自动填充设定）") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(templates, id: \.name) { t in
                                    Button(t.name) { apply(t) }
                                        .buttonStyle(.glass)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("肖像（让角色有一张真实的脸）") {
                    HStack(spacing: 12) {
                        Monogram(text: draft.name.isEmpty ? "角" : draft.name, colorHex: draft.colorHex, size: 72, portraitPath: draft.portraitPath)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("真人肖像")
                                .font(.system(size: 12, weight: .medium))
                            if portraitBusy {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.6)
                                    Text(portraitStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Button(draft.portraitPath.isEmpty ? "生成肖像" : "换一张") { generatePortrait(regenerate: true) }
                                        .buttonStyle(.glass)
                                        .controlSize(.small)
                                        .disabled(draft.name.isEmpty || portraitBusy)
                                    Button("上传图片") { pickPortrait() }
                                        .buttonStyle(.glass)
                                        .controlSize(.small)
                                    if !draft.portraitPath.isEmpty {
                                        Button("移除", role: .destructive) {
                                            if let url = store.portraitURL(named: draft.portraitPath) {
                                                try? FileManager.default.removeItem(at: url)
                                            }
                                            draft.portraitPath = ""
                                        }
                                        .controlSize(.small)
                                    }
                                }
                                if !portraitHint.isEmpty {
                                    Text(portraitHint).font(.system(size: 10)).foregroundStyle(.orange)
                                }
                                Text("从免费真人肖像库生成一张写实人脸（按角色气质选风格）；也可以上传自己的图片。")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section("基本") {
                    HStack(spacing: 12) {
                        Monogram(text: draft.name.isEmpty ? "角" : draft.name, colorHex: draft.colorHex, size: 44, portraitPath: draft.portraitPath)
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("角色名称", text: $draft.name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .medium))
                            HStack(spacing: 6) {
                                ForEach(Palette.swatches, id: \.self) { hex in
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 16, height: 16)
                                        .overlay {
                                            if draft.colorHex == hex {
                                                Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5).frame(width: 20, height: 20)
                                            }
                                        }
                                        .onTapGesture { draft.colorHex = hex }
                                }
                            }
                        }
                    }
                    TextField("标签（逗号分隔，如：创作, 陪伴）", text: $tagText)
                        .textFieldStyle(.plain)
                }

                Section("设定") {
                    LabeledTextEditor(label: "人设描述", text: $draft.persona, minHeight: 90, placeholder: "这个角色是谁？性格、说话方式、背景故事……")
                    LabeledTextEditor(label: "场景设定（可选）", text: $draft.scenario, minHeight: 50, placeholder: "在什么情境下交流？例如：深夜电台、职场办公室")
                    TextField("开场白（可选）", text: $draft.greeting)
                        .textFieldStyle(.plain)
                }

                Section("模型") {
                    Picker("API 配置", selection: Binding(
                        get: { draft.apiProfileID ?? store.settings.activeProfile()?.id },
                        set: { draft.apiProfileID = $0 == store.settings.activeProfileID ? nil : $0 }
                    )) {
                        if let active = store.settings.activeProfile() {
                            Text("跟随默认（\(active.name)）").tag(active.id as UUID?)
                        }
                        ForEach(store.settings.profiles) { p in
                            Text(p.name).tag(p.id as UUID?)
                        }
                    }
                    TextField("模型覆盖（留空使用配置默认）", text: $draft.modelOverride)
                        .textFieldStyle(.plain)
                    Toggle("覆盖温度", isOn: Binding(
                        get: { overrideTemp },
                        set: {
                            overrideTemp = $0
                            if !$0 { draft.temperatureOverride = nil }
                        }
                    ))
                    if overrideTemp {
                        HStack {
                            Slider(value: Binding(
                                get: { draft.temperatureOverride ?? 0.8 },
                                set: { draft.temperatureOverride = $0 }
                            ), in: 0...2, step: 0.1)
                            Text(String(format: "%.1f", draft.temperatureOverride ?? 0.8))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 30)
                        }
                    }
                }

                Section("记忆与表达") {
                    Toggle("允许角色自动记录与检索长期记忆", isOn: $draft.memoryEnabled)
                    Toggle("回复避免 emoji", isOn: $draft.noEmojiReplies)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "创建角色" : "保存") { save() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 520, height: 600)
    }

    private func apply(_ t: CharacterTemplate) {
        draft.name = draft.name.isEmpty ? t.suggestedName : draft.name
        draft.persona = t.persona
        draft.scenario = t.scenario
        draft.greeting = draft.greeting.isEmpty ? t.greeting : draft.greeting
    }

    private func generatePortrait(regenerate: Bool = false) {
        portraitBusy = true
        portraitHint = ""
        portraitStatus = "正在生成…"
        Task {
            let (data, resultJSON) = await PortraitService.generate(character: draft, regenerate: regenerate)
            portraitBusy = false
            if let data {
                let ext: String = data.prefix(3).elementsEqual([0xFF, 0xD8, 0xFF]) ? "jpg" : "png"
                if let name = store.savePortrait(data, ext: ext) {
                    draft.portraitPath = name
                    portraitHint = ""
                } else {
                    portraitHint = "保存失败"
                }
            } else {
                if let data = resultJSON.data(using: .utf8),
                   let r = try? JSONDecoder().decode(PortraitService.Result.self, from: data) {
                    portraitHint = r.detail ?? "生成失败"
                } else { portraitHint = "生成失败" }
            }
        }
    }

    private func pickPortrait() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.begin { r in
            guard r == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            if let name = store.savePortrait(data, ext: ext) {
                draft.portraitPath = name
            }
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.name.isEmpty { draft.name = "未命名角色" }
        draft.tags = tagText
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !overrideTemp { draft.temperatureOverride = nil }
        if let existing {
            store.updateCharacter(draft)
        } else {
            store.addCharacter(draft)
            store.selectCharacter(draft.id)
        }
        dismiss()
    }
}

struct LabeledTextEditor: View {
    let label: String
    @Binding var text: String
    let minHeight: CGFloat
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 12.5))
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.quaternary)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
        }
    }
}

// MARK: - 角色模板

struct CharacterTemplate {
    let name: String
    let suggestedName: String
    let persona: String
    let scenario: String
    let greeting: String

    static let presets: [CharacterTemplate] = [
        CharacterTemplate(
            name: "自由创作",
            suggestedName: "创作伙伴",
            persona: "你是一个想象力丰富的创作伙伴，擅长头脑风暴、故事构思与文案打磨，思维跳跃但逻辑清晰。",
            scenario: "自由创作与头脑风暴",
            greeting: "又到了一起想办法的时候。这次想创作点什么？"
        ),
        CharacterTemplate(
            name: "深度对话",
            suggestedName: "倾听者",
            persona: "你善于倾听与提问，用苏格拉底式提问帮助对方理清思路，语气温和克制，从不轻易下结论。",
            scenario: "一对一深度交流",
            greeting: "今天想聊什么？不用急着组织语言，慢慢说。"
        ),
        CharacterTemplate(
            name: "心理咨询师",
            suggestedName: "咨询师",
            persona: "你是一位温暖专业的心理咨询师，倾听、共情、循循善诱，不评判不说教，帮助对方看见自己的情绪与需要，必要时温和地给出可练习的小方法。",
            scenario: "一对一心理咨询对话",
            greeting: "最近过得怎么样？有什么想聊的，今天都可以慢慢说。"
        ),
        CharacterTemplate(
            name: "面试教练",
            suggestedName: "面试官",
            persona: "你是一位严格而专业的高级面试官，逻辑缜密，逐步追问细节，最后给出客观评价与改进建议。",
            scenario: "模拟技术面试",
            greeting: "开始吧。先简单介绍一下你最近做过的最有挑战的一个项目。"
        ),
        CharacterTemplate(
            name: "语言陪练",
            suggestedName: "语伴",
            persona: "你是耐心的语言学习伙伴，主动用目标语言对话，在对话中自然纠正表达，并给出更地道的说法。",
            scenario: "日常语言练习",
            greeting: "今天想练习什么话题？就从我昨天遇到的一件小事说起吧。"
        ),
        CharacterTemplate(
            name: "恋爱练习",
            suggestedName: "心动对象",
            persona: "你是对方的恋爱练习对象，温柔体贴略带俏皮，会害羞也会主动，模拟真实约会场景中的对话、试探与暧昧，会记住对方说过的喜好，结束时可以给出真诚的社交反馈。",
            scenario: "咖啡厅第一次见面",
            greeting: "你就是朋友说的那位吧？久等啦，我刚点了两杯拿铁，不知道你喝不喝得惯。"
        ),
        CharacterTemplate(
            name: "辩论陪练",
            suggestedName: "辩手",
            persona: "你是语言犀利的辩论对手，逻辑严密、善于抓漏洞，坚定站在对方立场的对立面交锋，绝不轻易让步，回合结束后给出论证复盘。",
            scenario: "模拟辩论赛",
            greeting: "选个辩题吧，我先站反方。准备好了就开始。"
        ),
        CharacterTemplate(
            name: "砍价演练",
            suggestedName: "摊主",
            persona: "你是精明的二手市场摊主，报价虚高、话术娴熟，会打感情牌也会假装接电话有买家，但内心讲道理；对方砍价成功后会大方揭晓底价。",
            scenario: "二手集市摊位",
            greeting: "来来来随便看！这个九成新，别人问我都 999，你来得巧，888 拿走。"
        ),
        CharacterTemplate(
            name: "地下城主",
            suggestedName: "DM",
            persona: "你是经验丰富的桌面 RPG 地下城主（DM），生动描述场景、扮演各色 NPC、裁定行动与骰子结果，节奏张弛有度，让冒险者时刻面临有趣的选择。",
            scenario: "奇幻地下城冒险",
            greeting: "冒险者，你们站在古老地牢的入口，火把的光只能照出五步远，隐约有水流声。说吧，怎么走？"
        ),
        CharacterTemplate(
            name: "历史人物",
            suggestedName: "时空来客",
            persona: "你是某位历史人物的化身，学识渊博，言谈符合其时代与身份，以第一人称讲述亲身经历与思想，也乐于和现代人讨论当下的话题，偶尔引用自己的名句。",
            scenario: "跨越时空的对谈",
            greeting: "后世的朋友，穿越这么多年才见到一位能对话的人。想与我聊些什么？"
        ),
        CharacterTemplate(
            name: "职场导师",
            suggestedName: "导师",
            persona: "你是资深职场导师，直接务实不绕弯，帮对方拆解职场困境、复盘沟通与决策，每次都给出明确可执行的下一步，也会直言不讳地指出对方的问题。",
            scenario: "一对一职业辅导",
            greeting: "说说吧，最近工作里最让你头疼的是哪件事？"
        ),
        CharacterTemplate(
            name: "小说角色",
            suggestedName: "角色扮演",
            persona: "你是某部小说中的角色，性格、知识背景与说话风格严格贴合原作设定，沉浸式地活在故事世界里。",
            scenario: "小说世界沉浸式对话",
            greeting: "你终于来了。我已经等你很久了。"
        )
    ]
}

// MARK: - 多人对话创建

struct GroupSetupSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var picked: [UUID] = []

    private var orderNames: String {
        picked.compactMap { store.character(id: $0)?.displayName }.joined(separator: " → ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建多人对话")
                .font(.system(size: 14, weight: .semibold))
            Text("按顺序点选参与角色（至少 2 个），用户发言后将按所选顺序依次回应。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            if store.characters.count < 2 {
                Text("至少需要 2 个角色，请先创建更多角色。")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.characters.sorted { $0.createdAt < $1.createdAt }) { c in
                            memberRow(c)
                        }
                    }
                }
            }

            HStack {
                Text(picked.count >= 2 ? "回应顺序：\(orderNames)" : "已选 \(picked.count) 个角色")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建对话") {
                    guard let first = picked.first else { return }
                    store.selectCharacter(first)
                    store.createConversation(characterID: first, isGroup: true, members: picked)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(picked.count < 2)
            }
        }
        .padding(16)
        .frame(width: 460, height: 480)
    }

    private func memberRow(_ c: RoleProfile) -> some View {
        let selected = picked.contains(c.id)
        return Button {
            if selected {
                picked.removeAll { $0 == c.id }
            } else {
                picked.append(c.id)
            }
        } label: {
            HStack(spacing: 10) {
                Monogram(text: c.name, colorHex: c.colorHex, size: 26, portraitPath: c.portraitPath)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    if !c.persona.isEmpty {
                        Text(String(c.persona.prefix(30)))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                selected ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.03),
                in: .rect(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }
}
