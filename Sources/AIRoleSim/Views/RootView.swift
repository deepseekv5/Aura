import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

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
                    .fill(Color(hex: character.colorHex).opacity(0.16))
                    .frame(width: 260, height: 260)
                    .blur(radius: 44)
                Monogram(text: character.name, colorHex: character.colorHex, size: 68)
            }
            Text(character.displayName)
                .font(.system(size: 22, weight: .medium))
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
    }
}

struct EmptyLanding: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text("Aura")
                .font(.system(size: 20, weight: .medium))
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
    }
}
