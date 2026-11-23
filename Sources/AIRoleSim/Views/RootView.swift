import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    /// 首次启动法律同意（版本 v1.0）
    @State private var showLegalConsent = false
    /// API 未配置引导（默认 API 模式）
    @State private var showAPIConfigGuide = false
    @State private var showUpdateView = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailArea()
        }
        .inspector(
            isPresented: Binding(
                get: { store.showMemoryInspector && store.selectedCharacterID != nil },
                set: { store.showMemoryInspector = $0 }
            )
        ) {
            MemoryInspector()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 460)
        }
        .sheet(isPresented: $store.showCharacterEditor) {
            CharacterEditorSheet(character: store.editingCharacterID.flatMap { store.character(id: $0) })
        }
        .sheet(isPresented: $store.showGroupSetup) {
            GroupSetupSheet()
        }
        .sheet(isPresented: $store.showSearch) {
            GlobalSearchSheet()
        }
        .sheet(isPresented: $showLegalConsent) {
            LegalConsentView {
                store.settings.legalConsentVersion = "1.0"
                showLegalConsent = false
                // 同意后立即检查 API 配置
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !store.settings.demoMode && !store.hasUsableAPIConfig() {
                        showAPIConfigGuide = true
                    }
                }
            }
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showAPIConfigGuide) {
            APIConfigGuideView { showAPIConfigGuide = false }
        }
        .sheet(isPresented: $showUpdateView) {
            UpdateView()
        }
        .onAppear {
            if store.settings.legalConsentVersion.isEmpty {
                showLegalConsent = true
            } else if !store.settings.demoMode && !store.hasUsableAPIConfig() {
                showAPIConfigGuide = true
            }
            // 启动自动检查更新（延迟 3 秒，不打扰首屏）
            if store.settings.autoCheckUpdates {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if let info = try? await UpdateService.check(), info != nil {
                        await MainActor.run { showUpdateView = true }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showUpdateView)) { _ in
            showUpdateView = true
        }
        // 当用户在设置中完成配置或开启演示模式后，自动关闭引导
        .onChange(of: store.hasUsableAPIConfig()) { _, has in
            if has { showAPIConfigGuide = false }
        }
        .onChange(of: store.settings.demoMode) { _, demo in
            if demo { showAPIConfigGuide = false }
        }
    }
}

struct DetailArea: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if let char = store.selectedCharacter() {
            if let convoID = store.selectedConversationID, store.conversation(id: convoID) != nil {
                ChatView(store: store, conversationID: convoID)
                    .id(convoID)
            } else {
                CharacterLanding(character: char)
            }
        } else {
            EmptyLanding()
        }
    }
}

struct CharacterLanding: View {
    @EnvironmentObject var store: AppStore
    let character: RoleProfile

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color(hex: character.colorHex).opacity(0.14))
                    .frame(width: 270, height: 270)
                    .blur(radius: 48)
                Circle()
                    .strokeBorder(Color(hex: character.colorHex).opacity(0.25), lineWidth: 1)
                    .frame(width: 148, height: 148)
                Monogram(text: character.name, colorHex: character.colorHex, size: 72, portraitPath: character.portraitPath)
            }
            Text(character.displayName)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            if !character.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(character.tags.prefix(4), id: \.self) { tag in
                        StatusBadge(text: tag, color: Color(hex: character.colorHex))
                    }
                }
            }
            GradientDivider(color: Color(hex: character.colorHex))
                .frame(width: 200)
            if !character.persona.isEmpty {
                Text(character.persona)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .frame(maxWidth: 440)
            }
            if !character.greeting.isEmpty {
                Text(character.greeting)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 440)
            }
            HStack(spacing: 10) {
                Button("开始对话") { store.newConversationForSelection() }
                    .buttonStyle(.glassProminent)
                Button("编辑角色") { store.editCharacter(character.id) }
                    .buttonStyle(.glass)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AmbientGlow(color: Color(hex: character.colorHex), radius: 380, opacity: 0.10)
                .offset(x: -260, y: -160)
            AmbientGlow(color: .purple, radius: 300, opacity: 0.07)
                .offset(x: 280, y: 180)
        }
    }
}

struct EmptyLanding: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 100, height: 100)
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                    .frame(width: 100, height: 100)
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundStyle(.secondary)
            }
            Text("Aura")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            GradientDivider().frame(width: 220)
            Text("AI 角色工坊 · 在左侧创建一个角色，随时开始对话。角色会自己记录并回忆长期记忆。")
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("新建角色") { store.beginNewCharacter() }
                .buttonStyle(.glassProminent)
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AmbientGlow(color: .blue, radius: 400, opacity: 0.09)
                .offset(x: -240, y: -150)
            AmbientGlow(color: .purple, radius: 320, opacity: 0.07)
                .offset(x: 280, y: 180)
        }
    }
}
