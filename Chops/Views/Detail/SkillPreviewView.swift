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

// MARK: - Rendered Markdown (NSTextView with dynamic height)

struct RenderedMarkdownView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> RenderedMarkdownContainer {
        RenderedMarkdownContainer()
    }

    func updateNSView(_ container: RenderedMarkdownContainer, context: Context) {
        let rendered = MarkdownRenderer.render(markdown)
        container.update(with: rendered)
    }
}

/// A self-sizing container that wraps an NSTextView and reports its height to SwiftUI.
final class RenderedMarkdownContainer: NSView {
    private let textView: NSTextView = {
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticLinkDetectionEnabled = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private var heightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(with attributed: NSAttributedString) {
        textView.textStorage?.setAttributedString(attributed)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Force the text container to use the current width
        textView.textContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedRect = textView.layoutManager!.usedRect(for: textView.textContainer!)
        let newHeight = ceil(usedRect.height)
        if abs(heightConstraint.constant - newHeight) > 1 {
            heightConstraint.constant = newHeight
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: heightConstraint.constant)
    }
}
