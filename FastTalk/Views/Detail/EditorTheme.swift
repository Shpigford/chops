import AppKit

enum EditorTheme {
    // MARK: - Editor Font

    static let editorFontSize: CGFloat = NSFont.systemFontSize
    static let editorFont = NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)

    // MARK: - Margins

    static let editorInsetX: CGFloat = 48
    static let editorInsetTop: CGFloat = 14

    // MARK: - Line Spacing

    static let lineSpacing: CGFloat = 6

    static var editorLineHeight: CGFloat {
        let font = editorFont
        return ceil(font.ascender - font.descender + font.leading) + lineSpacing
    }

    static var editorBaselineOffset: CGFloat {
        let font = editorFont
        let naturalHeight = ceil(font.ascender - font.descender + font.leading)
        return (editorLineHeight - naturalHeight) / 2
    }

    // MARK: - Dynamic Colors

    static let textColor = NSColor.textColor

    static let syntaxColor = NSColor.secondaryLabelColor
    static let headingColor = NSColor.labelColor
    static let boldColor = NSColor.labelColor
    static let italicColor = NSColor.secondaryLabelColor

    static let codeColor = NSColor(name: "editorCode") { appearance in
        appearance.isDark
            ? NSColor(red: 0.9, green: 0.45, blue: 0.45, alpha: 1)
            : NSColor(red: 0.75, green: 0.2, blue: 0.2, alpha: 1)
    }

    static let linkColor = NSColor.linkColor
    static let blockquoteColor = NSColor.tertiaryLabelColor
    static let frontmatterColor = NSColor.tertiaryLabelColor
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
