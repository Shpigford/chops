import Markdown
import AppKit

/// Walks a swift-markdown AST and produces a styled NSAttributedString.
struct MarkdownRenderer: MarkupWalker {
    private var result = NSMutableAttributedString()
    private var currentAttributes: [NSAttributedString.Key: Any] = [:]
    private var listDepth = 0
    private var orderedListCounters: [Int] = []
    private var isInOrderedList = false

    private static let headingSizes: [CGFloat] = [18, 16, 14, 13, 13, 13]
    private static let bodyFont = NSFont.systemFont(ofSize: 13)
    private static let bodyMonoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let textColor = NSColor.labelColor
    private static let secondaryColor = NSColor.secondaryLabelColor
    private static let codeBgColor = NSColor.quaternaryLabelColor

    // MARK: - Public API

    static func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var renderer = MarkdownRenderer()
        renderer.currentAttributes = [
            .font: bodyFont,
            .foregroundColor: textColor,
        ]
        renderer.visit(document)

        // Trim trailing newlines
        let mutable = NSMutableAttributedString(attributedString: renderer.result)
        while mutable.length > 0 && mutable.string.hasSuffix("\n") {
            mutable.deleteCharacters(in: NSRange(location: mutable.length - 1, length: 1))
        }
        return mutable
    }

    // MARK: - Block Nodes

    mutating func visitHeading(_ heading: Heading) {
        addBlockSpacingIfNeeded()
        let size = Self.headingSizes[min(heading.level - 1, 5)]
        let saved = currentAttributes
        currentAttributes[.font] = NSFont.systemFont(ofSize: size, weight: .bold)
        descendInto(heading)
        currentAttributes = saved
        appendNewline()
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        addBlockSpacingIfNeeded()
        descendInto(paragraph)
        appendNewline()
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        addBlockSpacingIfNeeded()
        let code = codeBlock.code.hasSuffix("\n")
            ? String(codeBlock.code.dropLast())
            : codeBlock.code

        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 12
        para.headIndent = 12
        para.tailIndent = -12
        para.paragraphSpacingBefore = 4
        para.paragraphSpacing = 4

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.bodyMonoFont,
            .foregroundColor: Self.textColor,
            .backgroundColor: Self.codeBgColor,
            .paragraphStyle: para,
        ]
        result.append(NSAttributedString(string: code, attributes: attrs))
        appendNewline()
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        addBlockSpacingIfNeeded()
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 20
        para.headIndent = 20

        let saved = currentAttributes
        currentAttributes[.foregroundColor] = Self.secondaryColor
        currentAttributes[.paragraphStyle] = para
        descendInto(blockQuote)
        currentAttributes = saved
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        addBlockSpacingIfNeeded()
        listDepth += 1
        orderedListCounters.append(Int(orderedList.startIndex))
        let savedOrdered = isInOrderedList
        isInOrderedList = true
        descendInto(orderedList)
        isInOrderedList = savedOrdered
        orderedListCounters.removeLast()
        listDepth -= 1
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        addBlockSpacingIfNeeded()
        listDepth += 1
        let savedOrdered = isInOrderedList
        isInOrderedList = false
        descendInto(unorderedList)
        isInOrderedList = savedOrdered
        listDepth -= 1
    }

    mutating func visitListItem(_ listItem: ListItem) {
        let indent = String(repeating: "    ", count: listDepth - 1)
        let bullet: String
        if isInOrderedList, !orderedListCounters.isEmpty {
            let num = orderedListCounters[orderedListCounters.count - 1]
            bullet = "\(indent)\(num). "
            orderedListCounters[orderedListCounters.count - 1] = num + 1
        } else {
            bullet = "\(indent)\u{2022} "
        }

        result.append(NSAttributedString(string: bullet, attributes: currentAttributes))
        descendInto(listItem)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        addBlockSpacingIfNeeded()
        let rule = String(repeating: "\u{2500}", count: 40)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.bodyFont,
            .foregroundColor: Self.secondaryColor,
        ]
        result.append(NSAttributedString(string: rule, attributes: attrs))
        appendNewline()
    }

    mutating func visitTable(_ table: Table) {
        addBlockSpacingIfNeeded()

        // Collect all rows (head + body)
        var allRows: [[String]] = []
        var columnCount = table.maxColumnCount

        // Head row
        let headRow = table.head
        var headCells: [String] = []
        for cell in headRow.cells {
            headCells.append(cell.plainText)
        }
        allRows.append(headCells)

        // Body rows
        for row in table.body.rows {
            var rowCells: [String] = []
            for cell in row.cells {
                rowCells.append(cell.plainText)
            }
            allRows.append(rowCells)
        }

        // Calculate column widths
        var colWidths = Array(repeating: 0, count: columnCount)
        for row in allRows {
            for (i, cell) in row.enumerated() where i < columnCount {
                colWidths[i] = max(colWidths[i], cell.count)
            }
        }

        let monoAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.bodyMonoFont,
            .foregroundColor: Self.textColor,
        ]
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: Self.textColor,
        ]

        for (rowIndex, row) in allRows.enumerated() {
            var line = ""
            for (i, cell) in row.enumerated() where i < columnCount {
                let padded = cell.padding(toLength: colWidths[i], withPad: " ", startingAt: 0)
                line += i == 0 ? padded : "  \(padded)"
            }
            let attrs = rowIndex == 0 ? headerAttrs : monoAttrs
            result.append(NSAttributedString(string: line, attributes: attrs))
            appendNewline()

            // Separator after header
            if rowIndex == 0 {
                var sep = ""
                for (i, width) in colWidths.enumerated() {
                    let dashes = String(repeating: "\u{2500}", count: width)
                    sep += i == 0 ? dashes : "  \(dashes)"
                }
                result.append(NSAttributedString(string: sep, attributes: monoAttrs))
                appendNewline()
            }
        }
    }

    // MARK: - Inline Nodes

    mutating func visitText(_ text: Text) {
        result.append(NSAttributedString(string: text.string, attributes: currentAttributes))
    }

    mutating func visitStrong(_ strong: Strong) {
        let saved = currentAttributes
        if let currentFont = currentAttributes[.font] as? NSFont {
            currentAttributes[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
        }
        descendInto(strong)
        currentAttributes = saved
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        let saved = currentAttributes
        if let currentFont = currentAttributes[.font] as? NSFont {
            currentAttributes[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
        }
        descendInto(emphasis)
        currentAttributes = saved
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        var attrs = currentAttributes
        attrs[.font] = Self.bodyMonoFont
        attrs[.backgroundColor] = Self.codeBgColor
        result.append(NSAttributedString(string: inlineCode.code, attributes: attrs))
    }

    mutating func visitLink(_ link: Link) {
        let saved = currentAttributes
        currentAttributes[.foregroundColor] = NSColor.controlAccentColor
        if let dest = link.destination, let url = URL(string: dest) {
            currentAttributes[.link] = url
        }
        descendInto(link)
        currentAttributes = saved
    }

    mutating func visitImage(_ image: Image) {
        let altText = image.plainText
        let display = altText.isEmpty ? "[image]" : "[\(altText)]"
        var attrs = currentAttributes
        attrs[.foregroundColor] = Self.secondaryColor
        result.append(NSAttributedString(string: display, attributes: attrs))
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        appendNewline()
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result.append(NSAttributedString(string: " ", attributes: currentAttributes))
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        let saved = currentAttributes
        currentAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        descendInto(strikethrough)
        currentAttributes = saved
    }

    // MARK: - Skip table sub-elements (handled in visitTable)

    mutating func visitTableHead(_ tableHead: Table.Head) {}
    mutating func visitTableBody(_ tableBody: Table.Body) {}
    mutating func visitTableRow(_ tableRow: Table.Row) {}
    mutating func visitTableCell(_ tableCell: Table.Cell) {}

    // MARK: - Helpers

    private mutating func appendNewline() {
        result.append(NSAttributedString(string: "\n", attributes: currentAttributes))
    }

    private mutating func addBlockSpacingIfNeeded() {
        guard result.length > 0 else { return }
        let str = result.string
        if !str.hasSuffix("\n\n") {
            if str.hasSuffix("\n") {
                appendNewline()
            } else {
                appendNewline()
                appendNewline()
            }
        }
    }
}
