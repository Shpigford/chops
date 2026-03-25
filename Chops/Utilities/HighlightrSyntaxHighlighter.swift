import MarkdownUI
import Highlightr
import SwiftUI

struct HighlightrSyntaxHighlighter: CodeSyntaxHighlighter {
    private static let shared: Highlightr = Highlightr()!

    private let highlightr: Highlightr

    init() {
        self.highlightr = Self.shared
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        highlightr.setTheme(to: isDark ? "atom-one-dark" : "atom-one-light")
    }

    func highlightCode(_ code: String, language: String?) -> Text {
        let lang = language ?? "plaintext"
        if let highlighted = highlightr.highlight(code, as: lang) {
            return Text(AttributedString(highlighted))
        }
        return Text(code)
    }
}
