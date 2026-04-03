# Views AGENTS.md

## Scope
- This file governs all code under `Chops/Views/`.
- Treat nested `AGENTS.md` files as stricter instructions for the corresponding subtree.

## UI System
- Preserve the current native macOS shell language: `NavigationSplitView`, toolbars, lists, grouped forms, sheets, popovers, `ContentUnavailableView`, and compact contextual menus.
- Keep the UI dense and readable rather than spacious and ornamental.
- Use small control sizes, secondary and tertiary text styling, and quiet grouped backgrounds before inventing custom chrome.
- Use monospaced text for technical content such as paths, logs, diffs, markdown, commands, and raw content previews.
- Reuse `ToolIcon` and `ToolBadge` for tool identity surfaces instead of hand-rolling new badges.

## State And Mutation
- Use `@Environment(AppState.self)` for shell selection and filter state.
- Use `@Environment(\\.modelContext)` for persisted mutations and save at the user-action boundary.
- Use `@Query` for view-driven lists that mirror SwiftData state.
- Keep view-local `@State` for ephemeral presentation, progress, and short-lived workflow state.

## AppKit Bridges
- Prefer SwiftUI first, then add narrow AppKit wrappers when the behavior is genuinely editor- or platform-specific.
- Keep AppKit bridges local to the subtree that needs them so the rest of the UI stays declarative.

## Reusable Shell Guidance
- For sibling-app features on this shell, reuse the current navigation, editor, diff, and settings primitives before inventing a parallel UI language.
- Add new views by fitting them into the existing shell rather than bypassing the split-view, settings-scene, or inline-workflow patterns already established here.

## Never
- Never move file I/O, SSH calls, or ACP transport logic into the view layer.
- Never create separate visual systems for similar surfaces that already have a reference implementation in this tree.
- Never hide data mutations in `onAppear` or rendering code when they belong to explicit user actions or service callbacks.

## Validation
- After editing any view subtree, build and visually inspect the changed flow in the running app.
