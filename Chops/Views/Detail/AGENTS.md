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
- Keep editor surfaces monospaced and document-like. Do not introduce a separate rich-text editing aesthetic in this subtree.
- Preserve the current preview model: WebKit, generated HTML, CSP that blocks JavaScript, and explicit link handoff to `NSWorkspace`.

## Data Flow
- Load from the actual file or SSH target through `SkillEditorDocument`; use cached `Skill` content only as fallback or mirror data.
- Keep remote editing routed through `SSHService` from the document object instead of building a second remote-edit abstraction in the view.
- Keep autosave explicit and delayed, not continuous on every keystroke.
- Route explicit save requests through the existing save notification and document save method.

## Compose And Metadata
- Keep the floating compose affordance and inline compose panel integrated into the detail pane rather than opening a separate window for the same workflow.
- Keep metadata display in `SkillMetadataBar` and use it as the reference for compact technical metadata presentation.
- When adding note-like or editor-adjacent features, integrate them with the current detail-pane ownership model instead of attaching free-floating state outside `SkillDetailView`.

## Never
- Never write directly to disk or SSH targets from random detail subviews when `SkillEditorDocument` already owns the edit lifecycle.
- Never fork the editor theme or markdown-highlighting behavior for a similar document surface in this subtree.
- Never weaken the preview sandbox by enabling arbitrary page JavaScript.

## Validation
- After editing this subtree, verify local editing, remote editing when relevant, preview mode, autosave, explicit save, metadata display, and compose-panel behavior.
