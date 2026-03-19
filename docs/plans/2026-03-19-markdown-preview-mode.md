# Markdown Preview Mode Implementation Plan

**Date**: 2026-03-19
**Status**: Draft
**Author**: Claude
**Spec**: `docs/superpowers/specs/2026-03-19-markdown-preview-mode-design.md`

## Overview

Add a read-only markdown preview mode to Chops. A toolbar toggle swaps the existing editor for a rendered view showing a frontmatter metadata card and fully styled markdown. Uses Apple's `swift-markdown` to parse the AST, with a custom `MarkdownRenderer` that walks it into `NSAttributedString`.

## Schematic Diagrams

### View Hierarchy (Preview Mode)

```
SkillDetailView
├── toolbar: [star] [folder] [book toggle]
├── @State isPreviewMode
│
├── SkillEditorView (isPreviewMode: $isPreviewMode)
│   ├── if !isPreviewMode:
│   │   └── HighlightedTextEditor (existing)
│   │       └── "Modified" badge
│   └── if isPreviewMode:
│       └── SkillPreviewView(content: editorContent)
│           ├── FrontmatterCardView (name, description, fields)
│           └── NSScrollView > NSTextView (read-only, attributed string)
│
├── Divider
└── SkillMetadataBar (always visible)
```

### Data Flow

```
editorContent (String)
       │
       ├──► FrontmatterParser.parse()
       │         │
       │         ├── .name, .description, .frontmatter → FrontmatterCardView
       │         └── .content (body without frontmatter)
       │                │
       │                ▼
       │         Document(parsing: content)   ← swift-markdown
       │                │
       │                ▼
       │         MarkdownRenderer.render(document) → NSAttributedString
       │                │
       │                ▼
       │         Read-only NSTextView
       │
       └──► HighlightedTextEditor (edit mode, unchanged)
```

## Implementation Phases

### Phase 1: Add swift-markdown dependency

**Complexity**: Low
**Dependencies**: None

#### Tasks

- [ ] Add `swift-markdown` package to `project.yml`
- [ ] Add target dependency with product name `Markdown`
- [ ] Run `xcodegen generate` to regenerate project
- [ ] Verify project builds with new dependency

#### Files to Create/Modify

| File | Changes |
|------|---------|
| `project.yml` | Add package + target dependency |

#### Code Example

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
  swift-markdown:
    url: https://github.com/apple/swift-markdown
    from: "0.5.0"

targets:
  Chops:
    # ...existing...
    dependencies:
      - package: Sparkle
      - package: swift-markdown
        product: Markdown
```

---

### Phase 2: Build MarkdownRenderer

**Complexity**: High
**Dependencies**: Phase 1

#### Tasks

- [ ] Create `MarkdownRenderer` struct implementing `MarkupWalker` from swift-markdown
- [ ] Implement heading rendering (H1-H6, bold, sized 18/16/14/13/13/13pt)
- [ ] Implement paragraph rendering with inter-block spacing
- [ ] Implement bold, italic, bold+italic via font traits
- [ ] Implement inline code (monospace + subtle background)
- [ ] Implement fenced code blocks (monospace, full-width background)
- [ ] Implement ordered and unordered lists with indentation
- [ ] Implement links (accent color, `.link` attribute)
- [ ] Implement blockquotes (indented, secondary color)
- [ ] Implement tables (aligned monospace columns)
- [ ] Implement horizontal rules (─── line, muted)
- [ ] Implement images (alt text in brackets)

#### Files to Create/Modify

| File | Changes |
|------|---------|
| `Chops/Utilities/MarkdownRenderer.swift` | New file — AST walker |

#### Code Example

```swift
import Markdown
import AppKit

struct MarkdownRenderer: MarkupWalker {
    private var result = NSMutableAttributedString()
    private let headingSizes: [CGFloat] = [18, 16, 14, 13, 13, 13]
    private let bodyFont = NSFont.systemFont(ofSize: 13)
    private let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    static func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var renderer = MarkdownRenderer()
        renderer.visit(document)
        return renderer.result
    }

    mutating func visitHeading(_ heading: Heading) {
        let size = headingSizes[min(heading.level - 1, 5)]
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        // append heading text with font, then paragraph spacing
        // ...
        descendInto(heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 8
        para.headIndent = 8
        para.tailIndent = -8
        // append code with monoFont + background
        // ...
    }

    // ... other visit methods
}
```

---

### Phase 3: Build SkillPreviewView

**Complexity**: Medium
**Dependencies**: Phase 2

#### Tasks

- [ ] Create `SkillPreviewView` that takes `content: String`
- [ ] Parse content with `FrontmatterParser` to split frontmatter from body
- [ ] Build frontmatter card view (name, description, other fields in a grid)
- [ ] Build read-only `NSTextView` wrapper for rendered markdown body
- [ ] Style frontmatter card with rounded rect, `quaternarySystemFill` background
- [ ] Handle edge case: no frontmatter (skip card, render full content)

#### Files to Create/Modify

| File | Changes |
|------|---------|
| `Chops/Views/Detail/SkillPreviewView.swift` | New file — preview + frontmatter card |

#### Code Example

```swift
import SwiftUI

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
            }
            .padding(20)
        }
    }
}

struct FrontmatterCardView: View {
    let parsed: ParsedSkill

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
            // other frontmatter fields as key-value grid
            let otherFields = parsed.frontmatter.filter { $0.key != "name" && $0.key != "description" }
            if !otherFields.isEmpty {
                Divider()
                ForEach(otherFields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(alignment: .top) {
                        Text(key).foregroundStyle(.tertiary).frame(width: 80, alignment: .trailing)
                        Text(value).foregroundStyle(.secondary)
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
```

The `RenderedMarkdownView` is an `NSViewRepresentable` wrapping a read-only `NSTextView`:

```swift
struct RenderedMarkdownView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        let rendered = MarkdownRenderer.render(markdown)
        textView.textStorage?.setAttributedString(rendered)
    }
}
```

---

### Phase 4: Wire up toggle in SkillDetailView and SkillEditorView

**Complexity**: Low
**Dependencies**: Phase 3

#### Tasks

- [ ] Add `@State private var isPreviewMode = false` to `SkillDetailView`
- [ ] Add book toggle button to toolbar
- [ ] Reset `isPreviewMode` to `false` on `onChange(of: skill.filePath)`
- [ ] Pass `isPreviewMode` as `@Binding` to `SkillEditorView`
- [ ] Update `SkillEditorView` to accept binding and conditionally show editor vs preview
- [ ] Verify Cmd+S is naturally a no-op in preview mode (focusedValue not set)

#### Files to Create/Modify

| File | Changes |
|------|---------|
| `Chops/Views/Detail/SkillDetailView.swift` | Add state, toolbar button, onChange reset, pass binding |
| `Chops/Views/Detail/SkillEditorView.swift` | Accept `isPreviewMode` binding, conditional view swap |

#### Code Example

**SkillDetailView.swift changes:**

```swift
struct SkillDetailView: View {
    @Bindable var skill: Skill
    @Environment(\.modelContext) private var modelContext
    @State private var isPreviewMode = false

    var body: some View {
        VStack(spacing: 0) {
            SkillEditorView(skill: skill, isPreviewMode: $isPreviewMode)
            Divider()
            SkillMetadataBar(skill: skill)
        }
        .navigationTitle(skill.name)
        .onChange(of: skill.filePath) {
            isPreviewMode = false
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isPreviewMode.toggle()
                } label: {
                    Image(systemName: isPreviewMode ? "book.fill" : "book")
                }
                .help(isPreviewMode ? "Edit" : "Preview")
            }
            // ...existing star and folder buttons
        }
    }
}
```

**SkillEditorView.swift changes:**

```swift
struct SkillEditorView: View {
    @Bindable var skill: Skill
    @Binding var isPreviewMode: Bool
    // ...existing state...

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isPreviewMode {
                SkillPreviewView(content: editorContent)
            } else {
                HighlightedTextEditor(text: $editorContent)

                if hasUnsavedChanges {
                    // ...existing Modified badge...
                }
            }
        }
        // ...existing modifiers...
    }
}
```

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| `swift-markdown` AST walker API differs from expected | Medium | Check actual `MarkupWalker` protocol before implementing; the library is well-documented |
| Complex tables render poorly in attributed strings | Low | Simple monospace column alignment is sufficient; tables in skill files are typically small |
| Large skill files cause slow preview rendering | Low | Render on toggle, not continuously; skill files are typically small (< 50KB) |
| `FrontmatterParser` strips quotes from values (e.g., `"description"`) | Low | Already working this way in the app; preview reuses same parser |

## Success Metrics

- Preview toggle button appears in toolbar alongside star and folder
- Clicking it swaps the editor for a rendered markdown view
- Frontmatter shows as a styled card with name, description, and other fields
- All CommonMark elements render correctly (headings, bold, code, lists, links, etc.)
- Switching skills resets back to edit mode
- Cmd+S does nothing in preview mode
- Light and dark mode both look correct

## Future Enhancements

- Keyboard shortcut for toggle (e.g., Cmd+Shift+P)
- Side-by-side split view option
- Scroll position sync between editor and preview
- Syntax-highlighted code blocks (language-aware coloring)
