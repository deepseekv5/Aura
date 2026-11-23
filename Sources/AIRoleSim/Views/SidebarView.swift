import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var pendingDelete: RoleProfile?

    private var filtered: [RoleProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.characters.sorted { $0.createdAt < $1.createdAt } }
        return store.characters.filter {
            $0.name.lowercased().contains(q)
                || $0.persona.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aura")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("角色")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                }
                Spacer()
                Button {
                    store.beginNewCharacter()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("新建角色")
            }
            // 光晕作为背景附加，不参与布局（避免撑高侧栏头部挤压列表）
            .background(alignment: .topTrailing) {
                AmbientGlow(color: .blue, radius: 140, opacity: 0.08)
                    .offset(x: 40, y: -30)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("搜索角色", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }

            List(
                selection: Binding(
                    get: { store.selectedCharacterID },
                    set: { if let id = $0 { store.selectCharacter(id) } }
                )
            ) {
                ForEach(filtered) { c in
                    SidebarRow(character: c, memoryCount: store.memories(for: c.id).count)
                        .tag(c.id)
                        .contextMenu { rowMenu(c) }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "还没有角色" : "没有匹配的角色",
                        systemImage: "person.2",
                        description: Text(query.isEmpty ? "点击右上角 + 创建" : "换个关键词试试")
                    )
                    .controlSize(.mini)
                }
            }

            Divider()

            HStack {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("设置")

                Spacer()

                if store.settings.demoMode {
                    StatusBadge(text: "演示模式", color: .orange, systemImage: "wand.and.stars")
                }
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .confirmationDialog(
            "删除「\(pendingDelete?.displayName ?? "")」？其全部对话与记忆将一并删除。",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let c = pendingDelete { store.deleteCharacter(c) }
                pendingDelete = nil
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ c: RoleProfile) -> some View {
        Button("新建对话") {
            store.selectCharacter(c.id)
            store.newConversationForSelection()
        }
        Button("编辑角色") { store.editCharacter(c.id) }
        Button("复制角色") { store.duplicateCharacter(c) }
        Divider()
        Button("删除角色", role: .destructive) { pendingDelete = c }
    }
}

private struct SidebarRow: View {
    @EnvironmentObject var store: AppStore
    let character: RoleProfile
    let memoryCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Monogram(text: character.name, colorHex: character.colorHex, size: 22, portraitPath: character.portraitPath)
            VStack(alignment: .leading, spacing: 1) {
                Text(character.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(memoryCount) 条记忆")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
