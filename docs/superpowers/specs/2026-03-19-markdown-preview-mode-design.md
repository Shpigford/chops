# Markdown Preview Mode — Design Spec

## Summary

Add a read-only markdown preview mode to the skill detail view. Users toggle between the existing editor and a rendered preview via a toolbar button. The preview displays a frontmatter metadata card followed by fully rendered markdown, using Apple's `swift-markdown` library to parse the AST and a custom renderer to produce styled `NSAttributedString`.

## Requirements

- Toggle between edit mode (existing editor) and preview mode (rendered markdown)
- Preview is read-only — no editing, no "Modified" badge, no Cmd+S
- YAML frontmatter is displayed as a styled metadata card (name, description, other fields)
- Full CommonMark rendering: headings, bold/italic, code blocks, inline code, lists, links, blockquotes, tables, horizontal rules
- Switching skills resets to edit mode
- Must save from edit mode (switch back to save)

## State & Toggle

- New `@State private var isPreviewMode: Bool = false` on `SkillEditorView`
- Resets to `false` on skill change (`onChange(of: skill)`)
- Toolbar in `SkillDetailView` gets a third button: SF Symbol `book` (unfilled) / `book.fill` (active)
- Placed alongside existing star and folder icons
- State passed as `@Binding` from `SkillDetailView` to `SkillEditorView`

## Frontmatter Card

- Strips YAML frontmatter from the rendered body
- Displays at the top of the preview as a styled card:
  - **Skill name** — large, bold title
  - **Description** — secondary color, regular weight
  - **Other frontmatter fields** — key-value pairs in a subtle grid
- Rounded rect background using `quaternarySystemFill`
- Omitted entirely if no frontmatter is present
- Reuses existing `FrontmatterParser` output — no new parsing logic

## Markdown Renderer

New `MarkdownRenderer` struct in `Chops/Utilities/MarkdownRenderer.swift`.

Walks a `swift-markdown` `Document` AST and produces `NSAttributedString`.

### Supported elements

| Element | Rendering |
|---------|-----------|
| Headings (H1-H4) | Bold, sized 18/16/14/13pt (matches editor highlighter) |
| Paragraphs | Regular weight, label color, spacing between blocks |
| Bold / Italic | Appropriate font traits |
| Inline code | Monospace + subtle background |
| Code blocks | Monospace, full-width subtle background, padding |
| Ordered lists | Indented with number prefixes |
| Unordered lists | Indented with bullet prefixes |
| Links | Accent color, clickable via `NSAttributedString.Key.link` |
| Blockquotes | Indented, secondary color, left indent effect |
| Tables | Aligned monospace text (simple column layout) |
| Horizontal rules | Line of `───` characters, muted color |
| Images | Alt text in brackets (no image loading) |

### Design notes

- Uses system colors (`NSColor.labelColor`, `.secondaryLabelColor`, etc.) for automatic light/dark mode support
- Base font: system font at 13pt (not monospace for body text, unlike the editor)
- Code elements use `NSFont.monospacedSystemFont`

## Preview View

New `SkillPreviewView` in `Chops/Views/Detail/SkillPreviewView.swift`.

- Takes a `Skill` as input
- Displays frontmatter card at top, then rendered markdown body below
- Body rendered in a read-only `NSTextView` wrapped in `NSScrollView` (consistent with editor approach)
- Not editable: no cursor, no selection for editing, no save support
- Selectable for copy

### Integration into SkillEditorView

`SkillEditorView` conditionally shows:
- `isPreviewMode == false` → `HighlightedTextEditor` (existing behavior)
- `isPreviewMode == true` → `SkillPreviewView`

Simple swap, no animation.

## Dependency

Add `apple/swift-markdown` (>= 0.5.0) via SPM in `project.yml`:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
  swift-markdown:
    url: https://github.com/apple/swift-markdown
    from: "0.5.0"
```

Add as a dependency to the Chops target.

## File Changes

### New files
- `Chops/Utilities/MarkdownRenderer.swift` — AST-to-NSAttributedString walker
- `Chops/Views/Detail/SkillPreviewView.swift` — read-only preview with frontmatter card + rendered body

### Modified files
- `project.yml` — add swift-markdown package and target dependency
- `Chops/Views/Detail/SkillDetailView.swift` — add book icon toggle button to toolbar
- `Chops/Views/Detail/SkillEditorView.swift` — add `isPreviewMode` state, conditionally show editor vs preview
