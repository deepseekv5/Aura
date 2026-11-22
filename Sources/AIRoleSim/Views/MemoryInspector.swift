import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MemoryInspector: View {
    @EnvironmentObject var store: AppStore

    @State private var editingMemory: MemoryEntry?
    @State private var creatingNew = false
    @State private var showEditor = false
    @State private var categoryFilter = "全部"
    @State private var summarizeStatus: String?
    @State private var pendingDelete: MemoryEntry?

    private var character: RoleProfile? { store.selectedCharacter() }
    private var allMemories: [MemoryEntry] {
        character.map { store.memories(for: $0.id) } ?? []
    }
    private var categories: [String] {
        Array(Set(allMemories.map { $0.category })).sorted()
    }
    private var filtered: [MemoryEntry] {
        let q = store.inspectorQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allMemories.filter { m in
            (categoryFilter == "全部" || m.category == categoryFilter)
                && (q.isEmpty || m.content.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            statLine
            filterBar

            if let status = summarizeStatus {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            ScrollView {
                VStack(spacing: 8) {
                    if filtered.isEmpty {
                        Text(allMemories.isEmpty ? "还没有记忆。角色会在对话中自动记录重要信息，你也可以手动添加。" : "没有匹配的记忆")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 30)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(filtered) { m in
                        MemoryCard(memory: m)
                            .contextMenu { cardMenu(m) }
                            .onTapGesture {
                                editingMemory = m
                                creatingNew = false
                                showEditor = true
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .sheet(isPresented: $showEditor) {
            MemoryEditorSheet(
                characterID: character?.id ?? UUID(),
                memory: creatingNew ? nil : editingMemory
            )
        }
        .confirmationDialog(
            "删除这条记忆？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let m = pendingDelete { store.deleteMemory(m) }
                pendingDelete = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("记忆")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                creatingNew = true
                editingMemory = nil
                showEditor = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("手动添加记忆")

            Menu {
                Button("从当前对话提炼记忆") {
                    Task { await runSummarize() }
                }
                Button("导出记忆 JSON") { exportJSON() }
                Divider()
                Button("清空该角色记忆", role: .destructive) {
                    if let c = character { store.clearMemories(characterID: c.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
        }
    }

    private var statLine: some View {
        Text("\(allMemories.count) 条记忆 · 置顶 \(allMemories.filter(\.pinned).count) 条")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            TextField("搜索记忆", text: $store.inspectorQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: .rect(cornerRadius: 7))
            Menu {
                Button("全部分类") { categoryFilter = "全部" }
                ForEach(categories, id: \.self) { c in
                    Button(c) { categoryFilter = c }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(categoryFilter)
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: .rect(cornerRadius: 7))
            }
            .buttonStyle(.borderless)
            .fixedSize()
        }
    }

    private func cardMenu(_ m: MemoryEntry) -> some View {
        Group {
            Button(m.pinned ? "取消置顶" : "置顶为核心记忆") { store.togglePin(m) }
            Button("编辑") {
                editingMemory = m
                creatingNew = false
                showEditor = true
            }
            Divider()
            Button("删除", role: .destructive) { pendingDelete = m }
        }
    }

    private func runSummarize() async {
        guard let c = character else { return }
        summarizeStatus = "正在提炼记忆…"
        do {
            let n = try await store.summarizeMemories(for: c.id)
            summarizeStatus = n > 0 ? "已从对话提炼 \(n) 条新记忆" : "没有提炼出新的记忆（可能已存在）"
        } catch {
            summarizeStatus = "提炼失败：\(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        summarizeStatus = nil
    }

    private func exportJSON() {
        guard let c = character else { return }
        let entries = store.memories(for: c.id)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(c.displayName)-记忆.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - 记忆卡片

struct MemoryCard: View {
    @EnvironmentObject var store: AppStore
    let memory: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                if memory.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
                Text(memory.content)
                    .font(.system(size: 12.5))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                Text(memory.category)
                    .font(.system(size: 9.5, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                ImportanceDots(value: memory.importance)
                Text(memory.sourceLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                if memory.useCount > 0 {
                    Text("用过 \(memory.useCount) 次")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.quaternary)
                }
                Spacer()
                Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(10)
        .glassPanel(12)
    }
}

// MARK: - 记忆编辑

struct MemoryEditorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let characterID: UUID
    let memory: MemoryEntry?

    @State private var content: String = ""
    @State private var category: String = "其他"
    @State private var importance: Int = 3
    @State private var pinned: Bool = false

    init(characterID: UUID, memory: MemoryEntry?) {
        self.characterID = characterID
        self.memory = memory
        if let m = memory {
            _content = State(initialValue: m.content)
            _category = State(initialValue: m.category)
            _importance = State(initialValue: m.importance)
            _pinned = State(initialValue: m.pinned)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(memory == nil ? "新增记忆" : "编辑记忆")
                .font(.system(size: 14, weight: .semibold))

            TextEditor(text: $content)
                .font(.system(size: 13))
                .frame(minHeight: 90)
                .padding(8)
                .background(.quaternary, in: .rect(cornerRadius: 10))

            HStack(spacing: 8) {
                Menu {
                    ForEach(MemoryEntry.categories, id: \.self) { c in
                        Button(c) { category = c }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(category).font(.system(size: 12))
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: .rect(cornerRadius: 7))
                }
                .buttonStyle(.borderless)

                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        Button {
                            importance = i + 1
                        } label: {
                            Image(systemName: i < importance ? "circle.fill" : "circle")
                                .font(.system(size: 9))
                                .foregroundStyle(i < importance ? Color.accentColor : Color.primary.opacity(0.2))
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Spacer()

                Toggle("核心", isOn: $pinned)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(memory == nil ? "添加" : "保存") {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if let m = memory {
                        var updated = m
                        updated.content = trimmed
                        updated.category = category
                        updated.importance = importance
                        updated.pinned = pinned
                        store.updateMemory(updated)
                    } else {
                        store.addMemory(
                            characterID: characterID,
                            content: trimmed,
                            category: category,
                            importance: importance,
                            pinned: pinned,
                            source: "manual"
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
