import AppKit

final class ChopsTextView: NSTextView {

    // MARK: - Cursor

    override func mouseMoved(with event: NSEvent) {
        // If another view (e.g. a floating button) is in front at this point, don't set the I-beam.
        if let hitView = window?.contentView?.hitTest(event.locationInWindow),
           hitView !== self, !(hitView is NSClipView) {
            return
        }
        super.mouseMoved(with: event)
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if let indicator = subview as? NSTextInsertionIndicator {
            indicator.displayMode = .hidden
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var adjusted = rect
        adjusted.size.width = 2
        super.drawInsertionPoint(in: adjusted, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var rect = rect
        rect.size.width += 2
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }

    // MARK: - Find

    @objc func showFindPanel(_ sender: Any?) {
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        performFindPanelAction(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers == "f" {
            showFindPanel(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Markdown Formatting

    @objc func toggleBold(_ sender: Any?) {
        wrapSelection(prefix: "**", suffix: "**", placeholder: "bold text")
    }

    @objc func toggleItalic(_ sender: Any?) {
        wrapSelection(prefix: "*", suffix: "*", placeholder: "italic text")
    }

    @objc func insertLink(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            insertText("[link text](url)", replacementRange: range)
            let urlStart = range.location + "[link text](".utf16.count
            setSelectedRange(NSRange(location: urlStart, length: "url".utf16.count))
        } else {
            insertText("[\(selected)](url)", replacementRange: range)
            let urlStart = range.location + "[\(selected)](".utf16.count
            setSelectedRange(NSRange(location: urlStart, length: "url".utf16.count))
        }
    }

    @objc func insertHeading(_ sender: Any?) {
        let range = selectedRange()
        let lineRange = (string as NSString).lineRange(for: range)
        let line = (string as NSString).substring(with: lineRange)

        let trimmed = line.drop(while: { $0 == "#" || $0 == " " })
        let hashes = line.prefix(while: { $0 == "#" })

        let newLine: String
        switch hashes.count {
        case 0: newLine = "# \(trimmed)"
        case 1: newLine = "## \(trimmed)"
        case 2: newLine = "### \(trimmed)"
        default: newLine = String(trimmed)
        }

        insertText(newLine, replacementRange: lineRange)
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        wrapSelection(prefix: "~~", suffix: "~~", placeholder: "strikethrough text")
    }

    @objc func toggleBulletList(_ sender: Any?) {
        toggleLinePrefix(prefix: "- ", placeholder: "list item")
    }

    @objc func toggleNumberedList(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            insertText("1. list item", replacementRange: range)
            let start = range.location + "1. ".utf16.count
            setSelectedRange(NSRange(location: start, length: "list item".utf16.count))
            return
        }
        let lineRange = (string as NSString).lineRange(for: range)
        let block = (string as NSString).substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        var result: [String] = []
        var num = 1
        for line in lines {
            if line.isEmpty {
                result.append(line)
            } else {
                result.append("\(num). \(line)")
                num += 1
            }
        }
        insertText(result.joined(separator: "\n"), replacementRange: lineRange)
    }

    @objc func toggleTodoList(_ sender: Any?) {
        toggleLinePrefix(prefix: "- [ ] ", placeholder: "task")
    }

    @objc func toggleBlockquote(_ sender: Any?) {
        toggleLinePrefix(prefix: "> ", placeholder: "quote")
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        let range = selectedRange()
        insertText("\n\n---\n\n", replacementRange: range)
    }

    @objc func insertMarkdownTable(_ sender: Any?) {
        let range = selectedRange()
        let table = "| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| Cell | Cell | Cell |"
        insertText(table, replacementRange: range)
    }

    @objc func toggleInlineCode(_ sender: Any?) {
        wrapSelection(prefix: "`", suffix: "`", placeholder: "code")
    }

    @objc func insertCodeBlock(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            let snippet = "```\ncode\n```"
            insertText(snippet, replacementRange: range)
            let start = range.location + "```\n".utf16.count
            setSelectedRange(NSRange(location: start, length: "code".utf16.count))
        } else {
            insertText("```\n\(selected)\n```", replacementRange: range)
        }
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        let formatMenu = NSMenu(title: "Text Format")

        formatMenu.addItem(withTitle: "Headers", action: #selector(insertHeading(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        let boldItem = formatMenu.addItem(withTitle: "Bold", action: #selector(toggleBold(_:)), keyEquivalent: "b")
        boldItem.keyEquivalentModifierMask = .command
        let italicItem = formatMenu.addItem(withTitle: "Italic", action: #selector(toggleItalic(_:)), keyEquivalent: "i")
        italicItem.keyEquivalentModifierMask = .command
        let strikeItem = formatMenu.addItem(withTitle: "Strikethrough", action: #selector(toggleStrikethrough(_:)), keyEquivalent: "x")
        strikeItem.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "Insert Link", action: #selector(insertLink(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "List", action: #selector(toggleBulletList(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Ordered List", action: #selector(toggleNumberedList(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Todo", action: #selector(toggleTodoList(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "Quote", action: #selector(toggleBlockquote(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Horizontal Rule", action: #selector(insertHorizontalRule(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Table", action: #selector(insertMarkdownTable(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "Code", action: #selector(toggleInlineCode(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Code Block", action: #selector(insertCodeBlock(_:)), keyEquivalent: "")

        let formatItem = NSMenuItem(title: "Text Format", action: nil, keyEquivalent: "")
        formatItem.submenu = formatMenu

        menu.insertItem(.separator(), at: 0)
        menu.insertItem(formatItem, at: 0)

        return menu
    }

    // MARK: - Helpers

    private func toggleLinePrefix(prefix: String, placeholder: String) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            let text = "\(prefix)\(placeholder)"
            insertText(text, replacementRange: range)
            let start = range.location + prefix.utf16.count
            setSelectedRange(NSRange(location: start, length: placeholder.utf16.count))
            return
        }
        let lineRange = (string as NSString).lineRange(for: range)
        let block = (string as NSString).substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        let result = lines.map { $0.isEmpty ? $0 : "\(prefix)\($0)" }
        insertText(result.joined(separator: "\n"), replacementRange: lineRange)
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            let text = "\(prefix)\(placeholder)\(suffix)"
            insertText(text, replacementRange: range)
            let placeholderStart = range.location + prefix.utf16.count
            setSelectedRange(NSRange(location: placeholderStart, length: placeholder.utf16.count))
        } else {
            let text = "\(prefix)\(selected)\(suffix)"
            insertText(text, replacementRange: range)
        }
    }
}
