import SwiftUI
import AppKit

struct SkillPreviewView: View {
    let content: String

    private var parsed: ParsedSkill {
        FrontmatterParser.parse(content)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !parsed.frontmatter.isEmpty {
                    FrontmatterCardView(parsed: parsed)
                }

                RenderedMarkdownView(markdown: parsed.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Frontmatter Card

struct FrontmatterCardView: View {
    let parsed: ParsedSkill

    private var otherFields: [(key: String, value: String)] {
        parsed.frontmatter
            .filter { $0.key != "name" && $0.key != "description" }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !parsed.name.isEmpty {
                Text(parsed.name)
                    .font(.title2.bold())
            }
            if !parsed.description.isEmpty {
                Text(parsed.description)
                    .foregroundStyle(.secondary)
            }
            if !otherFields.isEmpty {
                Divider()
                ForEach(otherFields, id: \.key) { field in
                    HStack(alignment: .top, spacing: 8) {
                        Text(field.key)
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .trailing)
                        Text(field.value)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Rendered Markdown (read-only NSTextView)

struct RenderedMarkdownView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticLinkDetectionEnabled = true

        // Wrap in a non-scrolling scroll view for proper layout
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autoresizesSubviews = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let rendered = MarkdownRenderer.render(markdown)
        textView.textStorage?.setAttributedString(rendered)
    }
}
