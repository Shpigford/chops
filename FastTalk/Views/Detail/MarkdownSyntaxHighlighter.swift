import AppKit

final class MarkdownSyntaxHighlighter: NSObject {

    private var isHighlighting = false

    // MARK: - Regex Patterns

    private static let frontmatterKeyRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^([\\w][\\w\\s.-]*)(:)",
        options: .anchorsMatchLines
    )

    private static let patterns: [(NSRegularExpression, HighlightStyle)] = {
        var result: [(NSRegularExpression, HighlightStyle)] = []

        func add(_ pattern: String, _ style: HighlightStyle, options: NSRegularExpression.Options = []) {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                result.append((regex, style))
            }
        }

        // Frontmatter (--- ... ---) at very start of file
        add("\\A---[ \\t]*\\n([\\s\\S]*?)\\n---[ \\t]*(?:\\n|\\z)", .frontmatter)

        // Fenced code blocks (``` ... ```)
        add("^(`{3,})(.*?)\\n([\\s\\S]*?)^\\1\\s*$", .codeBlock, options: .anchorsMatchLines)

        // Headings: # Heading
        add("^(#{1,6}\\s+)(.+)$", .heading, options: .anchorsMatchLines)

        // Bold: **text** or __text__
        add("(\\*\\*|__)(.+?)(\\1)", .bold)

        // Italic: *text* or _text_
        add("(?<![\\w*])(\\*|_)(?!\\s)(.+?)(?<!\\s)\\1(?![\\w*])", .italic)

        // Strikethrough: ~~text~~
        add("(~~)(.+?)(~~)", .strikethrough)

        // Inline code: `code`
        add("(`+)(.+?)(\\1)", .inlineCode)

        // Links: [text](url)
        add("(\\[)(.+?)(\\]\\(.+?\\))", .link)

        // Blockquotes: > text
        add("^(>+\\s?)(.*)$", .blockquote, options: .anchorsMatchLines)

        // Unordered list markers: - or * or +
        add("^(\\s*[-*+]\\s)", .listMarker, options: .anchorsMatchLines)

        // Ordered list markers: 1.
        add("^(\\s*\\d+\\.\\s)", .listMarker, options: .anchorsMatchLines)

        // Task list: - [ ] or - [x]
        add("^(\\s*[-*+]\\s\\[[ xX]\\]\\s)", .listMarker, options: .anchorsMatchLines)

        // Horizontal rule
        add("^([-*_]{3,})\\s*$", .syntax, options: .anchorsMatchLines)

        return result
    }()

    // MARK: - Highlight Styles

    private enum HighlightStyle {
        case heading
        case bold
        case italic
        case strikethrough
        case inlineCode
        case codeBlock
        case link
        case blockquote
        case listMarker
        case syntax
        case frontmatter
    }

    // MARK: - Highlighting

    func highlightAll(_ textStorage: NSTextStorage) {
        guard !isHighlighting else { return }
        isHighlighting = true
        defer { isHighlighting = false }

        textStorage.beginEditing()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        // Reset to default style
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = EditorTheme.editorLineHeight
        paragraph.maximumLineHeight = EditorTheme.editorLineHeight

        textStorage.setAttributes([
            .font: EditorTheme.editorFont,
            .foregroundColor: EditorTheme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: EditorTheme.editorBaselineOffset
        ], range: fullRange)

        // Track code/frontmatter block ranges to skip inner highlighting
        var codeBlockRanges: [NSRange] = []

        for (regex, style) in Self.patterns {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match = match else { return }

                // Skip if inside a protected block (unless this IS a protected block pattern)
                if style != .codeBlock && style != .frontmatter {
                    let matchRange = match.range
                    if codeBlockRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) {
                        return
                    }
                }

                switch style {
                case .heading:
                    if match.numberOfRanges >= 3 {
                        let syntaxRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: syntaxRange)
                        textStorage.addAttributes([
                            .foregroundColor: EditorTheme.headingColor,
                            .font: NSFont.monospacedSystemFont(ofSize: EditorTheme.editorFontSize * 1.3, weight: .bold)
                        ], range: contentRange)
                    }

                case .bold:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            .foregroundColor: EditorTheme.boldColor,
                            .font: NSFont.monospacedSystemFont(ofSize: EditorTheme.editorFontSize, weight: .bold)
                        ], range: contentRange)
                    }

                case .italic:
                    if match.numberOfRanges >= 3 {
                        let syntaxRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: syntaxRange)
                        let closingStart = match.range(at: 2).upperBound
                        let closingRange = NSRange(location: closingStart, length: match.range(at: 1).length)
                        if closingRange.upperBound <= textStorage.length {
                            textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: closingRange)
                        }
                        let italicFont = NSFontManager.shared.convert(EditorTheme.editorFont, toHaveTrait: .italicFontMask)
                        textStorage.addAttributes([
                            .foregroundColor: EditorTheme.italicColor,
                            .font: italicFont
                        ], range: contentRange)
                    }

                case .strikethrough:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: EditorTheme.syntaxColor
                        ], range: contentRange)
                    }

                case .inlineCode:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.codeColor, range: contentRange)
                    }

                case .codeBlock:
                    codeBlockRanges.append(match.range)
                    textStorage.addAttribute(.foregroundColor, value: EditorTheme.codeColor, range: match.range)
                    if match.numberOfRanges >= 2 {
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: match.range(at: 1))
                    }

                case .link:
                    if match.numberOfRanges >= 4 {
                        let bracketRange = match.range(at: 1)
                        let textRange = match.range(at: 2)
                        let urlPartRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: bracketRange)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.linkColor, range: textRange)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: urlPartRange)
                    }

                case .blockquote:
                    if match.numberOfRanges >= 3 {
                        let markerRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: markerRange)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.blockquoteColor, range: contentRange)
                    }

                case .listMarker:
                    textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: match.range)

                case .syntax:
                    textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: match.range)

                case .frontmatter:
                    guard matchedText(text, range: match.range).hasPrefix("---") else { return }
                    codeBlockRanges.append(match.range)
                    let nsText = text as NSString
                    textStorage.addAttribute(.foregroundColor, value: EditorTheme.frontmatterColor, range: match.range)
                    // Color the opening --- delimiter
                    let openLineEnd = nsText.range(of: "\n", range: NSRange(location: match.range.location, length: match.range.length))
                    if openLineEnd.location != NSNotFound {
                        let openRange = NSRange(location: match.range.location, length: openLineEnd.location - match.range.location)
                        textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: openRange)
                    }
                    // Color the closing --- delimiter
                    let matchStr = nsText.substring(with: match.range) as NSString
                    let lastNewline = matchStr.range(of: "\n", options: .backwards)
                    if lastNewline.location != NSNotFound {
                        let closeStart = match.range.location + lastNewline.location + 1
                        let closeLen = match.range.location + match.range.length - closeStart
                        if closeLen > 0 {
                            let closeRange = NSRange(location: closeStart, length: closeLen)
                            textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: closeRange)
                        }
                    }
                    // Color YAML keys within the body
                    if match.numberOfRanges >= 2 {
                        let bodyRange = match.range(at: 1)
                        if bodyRange.location != NSNotFound, let keyRegex = Self.frontmatterKeyRegex {
                            keyRegex.enumerateMatches(in: text, range: bodyRange) { keyMatch, _, _ in
                                guard let keyMatch = keyMatch, keyMatch.numberOfRanges >= 3 else { return }
                                textStorage.addAttribute(.foregroundColor, value: EditorTheme.headingColor, range: keyMatch.range(at: 1))
                                textStorage.addAttribute(.foregroundColor, value: EditorTheme.syntaxColor, range: keyMatch.range(at: 2))
                            }
                        }
                    }
                }
            }
        }

        textStorage.endEditing()
    }

    private func matchedText(_ text: String, range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }
}
