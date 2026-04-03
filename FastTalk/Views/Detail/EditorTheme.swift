import AppKit

enum EditorTheme {
    // MARK: - Editor Font

    static let editorFontSize: CGFloat = 13
    static let editorFont = NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)

    // MARK: - Margins

    static let editorInsetX: CGFloat = 48
    static let editorInsetTop: CGFloat = 12

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

    static let textColor = NSColor(name: "editorText") { appearance in
        appearance.isDark
            ? NSColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 1)
            : NSColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1)
    }

    static let syntaxColor = NSColor(name: "editorSyntax") { appearance in
        appearance.isDark
            ? NSColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
            : NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
    }

    static let headingColor = NSColor(name: "editorHeading") { appearance in
        appearance.isDark
            ? NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
            : NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    }

    static let boldColor = NSColor(name: "editorBold") { appearance in
        appearance.isDark
            ? NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
            : NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    }

    static let italicColor = NSColor(name: "editorItalic") { appearance in
        appearance.isDark
            ? NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
            : NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)
    }

    static let codeColor = NSColor(name: "editorCode") { appearance in
        appearance.isDark
            ? NSColor(red: 0.9, green: 0.45, blue: 0.45, alpha: 1)
            : NSColor(red: 0.75, green: 0.2, blue: 0.2, alpha: 1)
    }

    static let linkColor = NSColor(name: "editorLink") { appearance in
        appearance.isDark
            ? NSColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1)
            : NSColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1)
    }

    static let blockquoteColor = NSColor(name: "editorBlockquote") { appearance in
        appearance.isDark
            ? NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
            : NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
    }

    static let frontmatterColor = NSColor(name: "editorFrontmatter") { appearance in
        appearance.isDark
            ? NSColor(red: 0.55, green: 0.55, blue: 0.65, alpha: 1)
            : NSColor(red: 0.35, green: 0.35, blue: 0.5, alpha: 1)
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
