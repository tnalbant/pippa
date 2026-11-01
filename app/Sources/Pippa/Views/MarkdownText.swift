import SwiftUI

/// The answer's Markdown as blocks: paragraphs, headings, lists, quotes, code and tables. Small models write all of
/// these; inline-only parsing showed "## Überblick" and "- item" literally.
struct MarkdownText: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level <= 1 ? .title3.weight(.semibold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•").foregroundStyle(.secondary).monospacedDigit()
                            .frame(minWidth: ordered ? 18 : 10, alignment: .trailing)
                        Text(Self.inline(item.text)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 18)
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.chatBorder).frame(width: 3)
                Text(Self.inline(text)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.system(.callout, design: .monospaced)).padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.chatInset, in: RoundedRectangle(cornerRadius: 8))
        case .table(let header, let rows):
            MarkdownTable(header: header, rows: rows)
        case .rule:
            Divider()
        }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct MarkdownTable: View {
    var header: [String]
    var rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, cell in self.cell(cell, bold: true) } }
                    .background(Theme.chatInset)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(0..<header.count, id: \.self) { column in self.cell(column < row.count ? row[column] : "", bold: false) }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.chatBorder))
        }
    }

    private func cell(_ text: String, bold: Bool) -> some View {
        Text(MarkdownText.inline(text)).fontWeight(bold ? .semibold : .regular)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: 280, alignment: .leading)
    }
}

enum MarkdownBlock: Equatable {
    struct Item: Equatable { var text: String; var indent: Int }
    case paragraph(String)
    case heading(Int, String)
    case list([Item], ordered: Bool)
    case quote(String)
    case code(String)
    case table([String], [[String]])
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var items: [Item] = []
        var ordered = false
        var lines = text.components(separatedBy: "\n")[...]

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !items.isEmpty { blocks.append(.list(items, ordered: ordered)); items = [] }
        }

        while let raw = lines.popFirst() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = (raw.prefix { $0 == " " || $0 == "\t" }.count) / 2
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("```") {
                flush()
                var code: [String] = []
                while let next = lines.popFirst(), !next.trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(next) }
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }
            if let heading = headingLevel(line) {
                flush()
                blocks.append(.heading(heading, String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line == "---" || line == "***" || line == "___" { flush(); blocks.append(.rule); continue }
            if line.hasPrefix("|"), let next = lines.first, isTableSeparator(next) {
                flush()
                lines.removeFirst()
                var rows: [[String]] = []
                while let row = lines.first, row.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(row)); lines.removeFirst()
                }
                blocks.append(.table(cells(line), rows))
                continue
            }
            if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let item = bullet(line) {
                if !paragraph.isEmpty || (!items.isEmpty && ordered) { flush() }
                ordered = false
                items.append(Item(text: item, indent: indent))
                continue
            }
            if let item = numbered(line) {
                if !paragraph.isEmpty || (!items.isEmpty && !ordered) { flush() }
                ordered = true
                items.append(Item(text: item, indent: indent))
                continue
            }
            // A line right after a list item continues it.
            if !items.isEmpty, indent > 0 { items[items.count - 1].text += " " + line; continue }
            if !items.isEmpty { flush() }
            paragraph.append(line)
        }
        flush()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "• ", "+ "] where line.hasPrefix(marker) { return String(line.dropFirst(marker.count)) }
        return nil
    }

    private static func numbered(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.contains("-") && trimmed.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
