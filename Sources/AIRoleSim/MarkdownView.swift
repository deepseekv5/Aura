import SwiftUI

/// 轻量 Markdown 渲染器（零依赖）：
/// 支持 标题 / 表格 / 围栏代码块 / 无序有序列表 / 引用 / 分隔线 /
/// 行内 粗体、斜体、行内代码、链接（由 Foundation AttributedString 解析）。
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - 块级解析

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case code(language: String, code: String)
        case table(header: [String], rows: [[String]])
        case quote(String)
        case listItem(marker: String, text: String)
        case divider
    }

    private var blocks: [Block] {
        var out: [Block] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]

            // 围栏代码块
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let lang = line.trimmingCharacters(in: .whitespaces).dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // 跳过闭合围栏
                out.append(.code(language: String(lang), code: code.joined(separator: "\n")))
                continue
            }

            // 表格：当前行以 | 开头，下一行是分隔行
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                let header = parseTableRow(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(parseTableRow(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                out.append(.table(header: header, rows: rows))
                continue
            }

            // 标题
            if let h = headingOf(line) {
                out.append(h)
                i += 1
                continue
            }

            // 分隔线
            let compact = trimmed.replacingOccurrences(of: " ", with: "")
            if compact.count >= 3, Set(compact).isSubset(of: ["-", "*", "_"]) {
                out.append(.divider)
                i += 1
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(lines[i].trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            // 列表
            if let item = listItemOf(line) {
                out.append(item)
                i += 1
                continue
            }

            // 空行跳过；连续非空行合并为段落
            if trimmed.isEmpty {
                i += 1
                continue
            }
            var para: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l.hasPrefix("```") || l.hasPrefix("|") || l.hasPrefix("#") || l.hasPrefix(">") || l.hasPrefix("- ") || l.hasPrefix("* ") || listItemNumberOf(l) != nil || l.hasPrefix("---") {
                    break
                }
                para.append(l)
                i += 1
            }
            out.append(.paragraph(para.joined(separator: "\n")))
        }
        return out
    }

    private func headingOf(_ line: String) -> Block? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#") else { return nil }
        let level = t.prefix(while: { $0 == "#" }).count
        guard level >= 1 && level <= 4, let first = t.first, first == "#" else { return nil }
        let text = t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: level, text: String(text))
    }

    private func listItemOf(_ line: String) -> Block? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- ") || t.hasPrefix("* ") {
            return .listItem(marker: "•", text: String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        if let n = listItemNumberOf(t) {
            let after = t.dropFirst(n.count + 1)
            return .listItem(marker: n + ".", text: after.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func listItemNumberOf(_ t: String) -> String? {
        guard let r = t.range(of: "^\\d{1,2}\\. ", options: .regularExpression) else { return nil }
        return String(t[..<r.upperBound].dropLast(2)).trimmingCharacters(in: .whitespaces)
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return false }
        let inner = t.dropFirst().dropLast(t.hasSuffix("|") ? 1 : 0)
        return inner.split(separator: "|").allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && Set(c).isSubset(of: ["-", ":"])
        }
    }

    private func parseTableRow(_ line: String) -> [String] {
        var t = line
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - 块渲染

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(.system(size: level == 1 ? 17 : level == 2 ? 15.5 : 14.5, weight: .semibold))
                .padding(.top, 2)

        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: 13.5))
                .lineSpacing(4)

        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(language.isEmpty ? "代码" : language)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 9.5))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
            }
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .table(let header, let rows):
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        ForEach(Array(header.prefix(6).enumerated()), id: \.offset) { _, cell in
                            inlineText(cell)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(rows.prefix(12).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.prefix(6).enumerated()), id: \.offset) { _, cell in
                                inlineText(cell)
                                    .font(.system(size: 12.5))
                            }
                        }
                    }
                }
                .padding(10)
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .quote(let text):
            inlineText(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.accentColor.opacity(0.5)).frame(width: 3)
                }

        case .listItem(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(.system(size: marker.hasSuffix(".") ? 12.5 : 13))
                    .foregroundStyle(.secondary)
                inlineText(text)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
            }
            .padding(.leading, 6)

        case .divider:
            Divider()
        }
    }

    /// 行内 Markdown（粗体/斜体/行内代码/链接）→ AttributedString
    @ViewBuilder
    private func inlineText(_ text: String) -> some View {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )).map { Text($0) } ?? Text(text)
    }
}
