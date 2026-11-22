import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var store: AppStore
    @StateObject private var session: ChatSessionModel

    let conversationID: UUID

    @State private var draft = ""
    @State private var pendingImages: [Data] = []
    @State private var blinkOn = true

    init(store: AppStore, conversationID: UUID) {
        self.store = store
        self.conversationID = conversationID
        _session = StateObject(wrappedValue: ChatSessionModel(store: store, conversationID: conversationID))
    }

    private var convo: Conversation? { store.conversation(id: conversationID) }
    private var ownerCharacter: RoleProfile? {
        convo.flatMap { store.character(id: $0.characterID) }
    }

    var body: some View {
        Group {
            if let convo = convo {
                VStack(spacing: 0) {
                    MessageListView(store: store, session: session, conversationID: conversationID)

                    if let error = session.errorMessage {
                        errorBanner(error)
                    }

                    if !pendingImages.isEmpty {
                        pendingImagesRow
                    }

                    if let err = SpeechDictationService.shared.errorMessage {
                        Text(err)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    InputBar(
                        session: session,
                        text: $draft,
                        placeholder: convo.isGroup ? "发到多人对话，⌘↩ 发送" : "输入消息，⌘↩ 发送（点麦克风可语音输入）",
                        onAttach: { attachImages() }
                    ) {
                        let imgs = pendingImages
                        session.send(draft, images: imgs)
                        draft = ""
                        pendingImages = []
                    }
                    .onChange(of: SpeechDictationService.shared.transcript) { _, newValue in
                        draft = newValue
                    }
                    .onChange(of: SpeechDictationService.shared.isListening) { _, listening in
                        if !listening, !SpeechDictationService.shared.transcript.isEmpty {
                            draft = SpeechDictationService.shared.transcript
                        }
                    }
                }
                .navigationTitle(convo.isGroup ? convo.title : (ownerCharacter?.displayName ?? "对话"))
                .navigationSubtitle(convo.isGroup ? (ownerCharacter?.displayName ?? "") : convo.title)
                .toolbar { toolbarItems(convo) }
            } else {
                EmptyLanding()
            }
        }
    }

    private var pendingImagesRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, data in
                if let img = NSImage(data: data) {
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button {
                            pendingImages.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.borderless)
                        .offset(x: 5, y: -5)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }

    private func attachImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = "选择要发给角色的图片"
        panel.begin { resp in
            guard resp == .OK else { return }
            for url in panel.urls.prefix(6) {
                if let data = try? Data(contentsOf: url) {
                    pendingImages.append(data)
                }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
            Button("重试") { session.regenerate() }
                .font(.system(size: 12))
                .buttonStyle(.borderless)
            Button {
                session.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.red.opacity(0.06), in: .rect(cornerRadius: 10))
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ convo: Conversation) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Section("历史对话") {
                    ForEach(store.conversations(for: convo.characterID)) { c in
                        Button(c.title) { store.selectedConversationID = c.id }
                    }
                }
                Divider()
                Button("新建对话") { store.newConversationForSelection() }
                Button("新建多人对话") { store.showGroupSetup = true }
                if !convo.messages.isEmpty {
                    Button("导出 Markdown") { exportMarkdown(convo) }
                }
                if !convo.isGroup {
                    Divider()
                    Button("删除当前对话", role: .destructive) { store.deleteConversation(convo.id) }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("历史对话")

            Button {
                store.showMemoryInspector.toggle()
            } label: {
                Image(systemName: "brain")
            }
            .help("记忆面板")

            Button {
                store.editCharacter(convo.characterID)
            } label: {
                Image(systemName: "person.crop.square")
            }
            .help("编辑角色")
        }
    }

    private func exportMarkdown(_ convo: Conversation) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(convo.title).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let md = store.exportMarkdown(conversationID: convo.id)
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - 消息列表

struct MessageListView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var session: ChatSessionModel
    let conversationID: UUID

    var body: some View {
        Group {
            if let convo = store.conversation(id: conversationID) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(convo.messages) { m in
                                MessageRow(
                                    store: store,
                                    session: session,
                                    message: m,
                                    isGroup: convo.isGroup,
                                    isLast: m.id == convo.messages.last?.id
                                )
                                .id(m.id)
                            }
                            if session.isStreaming {
                                PendingRow(session: session, isGroup: convo.isGroup)
                                    .id("pending")
                            }
                            Color.clear.frame(height: 8).id("bottom")
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: convo.messages.count)
                    }
                    .onChange(of: convo.messages.count) { _, _ in scrollToBottom(proxy) }
                    .onChange(of: session.pendingText) { _, _ in scrollToBottom(proxy) }
                    .onChange(of: session.statusText) { _, _ in scrollToBottom(proxy) }
                    .onAppear { scrollToBottom(proxy) }
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("bottom", anchor: .bottom)
    }
}

// MARK: - 消息行

struct MessageRow: View {
    @ObservedObject var store: AppStore
    @ObservedObject var session: ChatSessionModel
    @ObservedObject var audio = AudioPlayerManager.shared
    let message: ChatMessage
    let isGroup: Bool
    let isLast: Bool
    @State private var showEditSheet = false

    var body: some View {
        Group {
            if message.role == .user {
                userRow
            } else {
                assistantRow
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .sheet(isPresented: $showEditSheet) {
            EditMessageSheet(original: message) { newContent in
                session.editAndResend(messageID: message.id, newContent: newContent)
            }
        }
    }

    private var speaker: RoleProfile? {
        message.speakerID.flatMap { store.character(id: $0) }
    }

    private var userRow: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 80)
            Text(displayContent)
                .textSelection(.enabled)
                .font(.system(size: 13.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 4, topTrailingRadius: 14,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: store.selectedCharacter()?.colorHex ?? "#5B8DEF").opacity(0.30),
                                Color(hex: store.selectedCharacter()?.colorHex ?? "#5B8DEF").opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .frame(maxWidth: 480, alignment: .trailing)
        }
        .contextMenu {
            Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) }
            Button("编辑并重发") { showEditSheet = true }
            Divider()
            Button("删除", role: .destructive) {
                store.deleteMessage(conversationID: session.conversationID, messageID: message.id)
            }
        }
    }

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isGroup {
                HStack(spacing: 6) {
                    Monogram(text: speaker?.displayName ?? "角色", colorHex: speaker?.colorHex ?? "#8A8F98", size: 15)
                    Text(speaker?.displayName ?? "角色")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if !message.imagePaths.isEmpty {
                HStack(spacing: 8) {
                    ForEach(message.imagePaths, id: \.self) { path in
                        messageImage(path)
                    }
                }
            }
            if !displayContent.isEmpty {
                MarkdownView(markdown: displayContent)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: 620, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            if !message.memoryNotes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(message.memoryNotes.enumerated()), id: \.offset) { _, note in
                        MemoryChip(text: "已记忆 · " + String(note.prefix(20)))
                    }
                }
            }
            HStack(spacing: 8) {
                if !message.content.isEmpty {
                    Button {
                        Task { await audio.toggle(message: message, settings: store.settings) }
                    } label: {
                        Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(isSpeaking ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isSpeaking ? "停止朗读" : "朗读这条回复")
                }
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
        }
        .contextMenu {
            Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) }
            if isLast {
                Button("重新生成") { session.regenerate() }
            }
            Divider()
            Button("删除", role: .destructive) {
                store.deleteMessage(conversationID: session.conversationID, messageID: message.id)
            }
        }
    }

    private var isSpeaking: Bool {
        audio.playingMessageID == message.id
    }

    @State private var previewImage: NSImage?

    private func messageImage(_ path: String) -> some View {
        Group {
            if let img = NSImage(contentsOf: store.imageURL(named: path)) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .onTapGesture { previewImage = img }
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: Binding(
            get: { previewImage != nil },
            set: { if !$0 { previewImage = nil } }
        )) {
            if let img = previewImage {
                VStack(spacing: 10) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 520)
                    Button("关闭") { previewImage = nil }
                        .buttonStyle(.glass)
                }
                .padding(16)
            }
        }
    }

    /// 显示用文本：过滤推理标签与文本型工具调用残留（兼容旧数据）
    private var displayContent: String {
        PromptBuilder.stripTextToolCalls(PromptBuilder.stripThinking(message.content))
    }
}

// MARK: - 流式中的占位行

struct PendingRow: View {
    @ObservedObject var session: ChatSessionModel
    let isGroup: Bool
    @State private var blinkOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isGroup, let status = session.statusText, status.contains("「") {
                Text(status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if !session.pendingText.isEmpty {
                HStack(alignment: .bottom, spacing: 3) {
                    Text(session.pendingText)
                        .font(.system(size: 13.5))
                        .lineSpacing(4)
                        .frame(maxWidth: 620, alignment: .leading)
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2, height: 13)
                        .opacity(blinkOn ? 1 : 0.15)
                }
            }
            if let status = session.statusText {
                Text(status)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                blinkOn = false
            }
        }
    }
}

// MARK: - 输入栏（液态玻璃）

struct InputBar: View {
    @ObservedObject var session: ChatSessionModel
    @Binding var text: String
    let placeholder: String
    var onAttach: (() -> Void)?
    let onSend: () -> Void
    @ObservedObject var dictation = SpeechDictationService.shared

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let onAttach {
                    Button(action: onAttach) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("附加图片")
                }
                Button {
                    dictation.toggle()
                } label: {
                    Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 13))
                        .foregroundStyle(dictation.isListening ? Color.red : Color.secondary)
                        .scaleEffect(dictation.isListening ? 1.15 : 1)
                        .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: dictation.isListening)
                }
                .buttonStyle(.borderless)
                .help(dictation.isListening ? "停止听写" : "语音输入（听写）")
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))

                if session.isStreaming {
                    Button {
                        session.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(7)
                    }
                    .buttonStyle(.glass)
                    .help("停止生成")
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(7)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("发送")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .shadow(color: .black.opacity(0.10), radius: 14, y: 5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - 编辑消息

struct EditMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let original: ChatMessage
    @State private var content: String
    let onSave: (String) -> Void

    init(original: ChatMessage, onSave: @escaping (String) -> Void) {
        self.original = original
        self.onSave = onSave
        _content = State(initialValue: original.content)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("编辑并重发")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            TextEditor(text: $content)
                .font(.system(size: 13))
                .frame(minHeight: 110)
                .padding(8)
                .background(.quaternary, in: .rect(cornerRadius: 10))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存并重发") {
                    onSave(content)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 470)
    }
}
