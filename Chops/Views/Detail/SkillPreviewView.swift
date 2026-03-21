import SwiftUI
import MarkdownUI

struct SkillPreviewView: View {
    let content: String

    var body: some View {
        ScrollView {
            Markdown(strippedContent)
                .markdownCodeSyntaxHighlighter(HighlightrSyntaxHighlighter())
                .textSelection(.enabled)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var strippedContent: String {
        FrontmatterParser.parse(content).content
    }
}
