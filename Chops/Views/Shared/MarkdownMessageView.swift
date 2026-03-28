import SwiftUI

struct MarkdownMessageView: View {
    let text: String
    @State private var attributed: AttributedString?

    var body: some View {
        Text(attributed ?? AttributedString(text))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: text) {
                let normalized = normalize(text)
                attributed = (try? AttributedString(markdown: normalized, options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                ))) ?? AttributedString(normalized)
            }
    }

    private func normalize(_ input: String) -> String {
        var result = input
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .newlines)
    }
}
