# Detail Views AGENTS.md

## Scope
- This file governs `Chops/Views/Detail/`.
- Treat this subtree as the owner of the document-style detail pane: editor, preview, metadata bar, and detail-specific AppKit bridges.

## Ownership
- Keep `SkillDetailView` as the workflow owner for preview versus editor mode, autosave behavior, favorite/delete/global actions, metadata display, and compose-panel visibility.
- Keep `SkillEditorDocument` as the load/save boundary for local and remote document editing.
- Keep `SkillEditorView` focused on editor presentation and loading/saving state indicators.
- Keep `SkillPreviewView` focused on secure markdown preview rendering.

## Editor Design System
- Reuse `EditorTheme` for editor typography, insets, line spacing, baseline alignment, and dynamic colors.
- Reuse `ChopsTextView` when editing behavior requires native cursor, find-panel, insertion-point, or markdown-formatting support.
- Reuse `HighlightedTextEditor` for syntax-highlighted plain-text editing. Do not replace it with `TextEditor` when the surface still needs editor theming, NSTextView behavior, or synchronous highlighting.
- Keep editor surfaces monospaced and document-like. Do not introduce a separate rich-text editing aesthetic in this subtree.
- Keep notes title-first without adding a separate title field. New notes should open seeded with `# ` and place the insertion point after that prefix on first load.
- Preserve the current preview model: WebKit, generated HTML, CSP that blocks JavaScript, and explicit link handoff to `NSWorkspace`.

## Data Flow
- Load from the actual file or SSH target through `SkillEditorDocument`; use cached `Skill` content only as fallback or mirror data.
- Keep remote editing routed through `SSHService` from the document object instead of building a second remote-edit abstraction in the view.
- Keep autosave explicit and delayed, not continuous on every keystroke.
- Route explicit save requests through the existing save notification and document save method.
- After successful local or remote saves, keep the `Skill` mirror fields refreshed from parsed content so the list and metadata panes stay in sync without a full rescan.
- For notes, keep visible title and excerpt refreshed from editor content while the user types so the list behaves like a note-taking app instead of waiting for a later rename step.
- Keep load cancellation and generation-guard patterns intact when changing document load behavior so stale async results do not overwrite newer selections.

## Compose And Metadata
- Keep the floating compose affordance and inline compose panel integrated into the detail pane rather than opening a separate window for the same workflow.
- Keep metadata display in `SkillMetadataBar` and use it as the reference for compact technical metadata presentation.
- Keep the note footer terminology note-specific: use `Category` instead of `Collections` in the note metadata popover.
- When adding note-like or editor-adjacent features, integrate them with the current detail-pane ownership model instead of attaching free-floating state outside `SkillDetailView`.

## Never
- Never write directly to disk or SSH targets from random detail subviews when `SkillEditorDocument` already owns the edit lifecycle.
- Never fork the editor theme or markdown-highlighting behavior for a similar document surface in this subtree.
- Never reintroduce permanent-delete confirmation for ordinary local note or skill deletion in this pane. The current pattern is move to Trash plus undo.
- Never weaken the preview sandbox by enabling arbitrary page JavaScript.

## Validation
- After editing this subtree, verify local editing, remote editing when relevant, preview mode, autosave, explicit save, metadata display, and compose-panel behavior.
- If editor plumbing changed, verify syntax highlighting, cursor behavior, find support, and save-error presentation in addition to the content itself.
