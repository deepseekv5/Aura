import SwiftUI

struct GlobalSearchSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results = SearchResults()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                TextField("搜索角色、对话与记忆…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("输入关键词，回车即可查看全部匹配。")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    } else if results.isEmpty {
                        Text("没有结果")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.tertiary)
                    } else {
                        characterSection
                        memorySection
                        messageSection
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 580, height: 500)
        .onAppear { focused = true }
        .onChange(of: query) { _, newValue in
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms 防抖
                if !Task.isCancelled {
                    results = store.searchAll(newValue)
                }
            }
        }
        .onSubmit {
            // 回车选中首个结果
            if let c = results.characters.first {
                store.selectCharacter(c.id)
                dismiss()
            } else if let m = results.memories.first {
                store.selectCharacter(m.characterID)
                store.inspectorQuery = query
                store.showMemoryInspector = true
                dismiss()
            }
        }
    }

    private var characterSection: some View {
        Group {
            if !results.characters.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("角色")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                    ForEach(results.characters) { c in
                        Button {
                            store.selectCharacter(c.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Monogram(text: c.name, colorHex: c.colorHex, size: 22)
                                Text(c.displayName).font(.system(size: 13))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var memorySection: some View {
        Group {
            if !results.memories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("记忆")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                    ForEach(results.memories) { m in
                        Button {
                            store.selectCharacter(m.characterID)
                            store.inspectorQuery = query
                            store.showMemoryInspector = true
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "brain")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(m.content)
                                    .font(.system(size: 12.5))
                                    .lineLimit(1)
                                Spacer()
                                Text(store.character(id: m.characterID)?.displayName ?? "")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var messageSection: some View {
        Group {
            if !results.messages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("对话")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                    ForEach(results.messages) { h in
                        Button {
                            store.selectCharacter(h.characterID)
                            store.selectedConversationID = h.conversationID
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(h.conversationTitle)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(h.characterName)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(h.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.quaternary)
                                }
                                Text(h.snippet)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
