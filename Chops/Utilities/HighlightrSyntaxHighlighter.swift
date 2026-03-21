import MarkdownUI
import Highlightr
import SwiftUI

struct HighlightrSyntaxHighlighter: CodeSyntaxHighlighter {
    private let highlightr: Highlightr

    init() {
        let h = Highlightr()!
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        h.setTheme(to: isDark ? "atom-one-dark" : "atom-one-light")
        self.highlightr = h
    }

    func highlightCode(_ code: String, language: String?) -> Text {
        let lang = language ?? "plaintext"
        if let highlighted = highlightr.highlight(code, as: lang) {
            return Text(AttributedString(highlighted))
        }
        return Text(code)
    }
}
