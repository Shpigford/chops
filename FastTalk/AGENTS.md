# FastTalk AGENTS.md

## Scope
- This file governs all code under `FastTalk/`.
- Treat nested `AGENTS.md` files as stricter subtree overlays, not replacements for this file.

## Architecture
- Build on the existing shell: `FastTalkApp` wires scenes and the model container, `ContentView` owns shell coordination, services own I/O and integrations, models define persisted state and registries, utilities stay stateless, views stay presentation-focused.
- Treat external documents as the product data model. The app indexes and edits them; it does not own a separate canonical copy.
- Follow the current flow: filesystem or SSH content -> service scan/load -> SwiftData index -> `@Query` views -> targeted read/save through document or service code.
- Keep transient UI state in `AppState`. Keep persisted or integration state out of `AppState`.
- Keep `AppState` as one shared environment value created in `FastTalkApp`, not as a recreated feature-local store or singleton replacement.
- Keep long-running I/O and process work off the main actor. Keep SwiftData mutation and save points on the main actor unless a file explicitly proves a different pattern.

## Reusable Shell Patterns
- Reuse the current split-view macOS shell for sibling-app work: sidebar navigation, list pane, detail pane, searchable shell, sheets for creation/install flows, and a separate settings scene.
- Reuse the current document-style editing pattern for any new note-like or content-heavy surface: dedicated document object, explicit load/save lifecycle, autosave policy, and optional preview mode.
- Reuse the current inline assistant workflow pattern for AI-assisted editing: embedded panel, connection state in the panel, explicit diff review, and clear accepted/rejected write states.
- Reuse the current settings pattern for subsystem configuration: one root settings shell, narrow panes per subsystem, `@AppStorage` for small preferences, and notifications only when a setting invalidates app-wide state.

## UI Consistency
- Keep the UI native, dense, and calm. Prefer toolbars, grouped panels, lists, popovers, sheets, `ContentUnavailableView`, and standard macOS control sizing.
- Use monospaced text for technical content: editor text, diffs, paths, logs, raw markdown, and machine-readable metadata.
- Use secondary and tertiary foreground styles for supporting information instead of inventing custom color systems.
- Reuse existing tool visuals, metadata bars, chat bubbles, diff panels, and preview surfaces before inventing new ones.
- Reach for local AppKit bridges only when SwiftUI cannot provide the required behavior cleanly.

## Data And State
- Keep `Skill.resolvedPath` semantics intact. It is the identity boundary that merges symlinked installs, plugin installs, and remote records.
- Keep the canonical global skill location centered on `~/.agents/skills`. Local installs and registry installs fan out from that canonical directory through symlinks.
- Keep local notes filesystem-backed under `NotesService.notesDirectoryURL`. Notes use fixed timestamp filenames on disk while the visible title stays content-derived from markdown.
- Keep SwiftData focused on `Skill`, `SkillCollection`, and `RemoteServer` plus their derived helpers. Put workflow logic in services or document objects, not in schema definitions.
- Keep shell selection in `AppState` set-backed for the middle list and derive single-item detail from that selection. The detail pane is intentionally single-item only.
- Reuse the existing invalidation notifications when the meaning is the same: `saveCurrentSkill` for explicit save requests and `customScanPathsChanged` for scan-affecting settings or installs.
- Reuse `newNoteRequested` when a shell-level command should trigger the same direct note-creation flow as the Notes toolbar.
- Add new app-wide invalidation notifications only when neither existing notification matches the meaning. Prefer extending the existing scan/save pathways over inventing parallel ones.

## Validation
- Validate changed shell flows end-to-end, not only individual functions.
- When touching code that spans services, models, and views, test the actual user journey through the app shell instead of spot-checking isolated pieces.
- After structural changes, verify the full path from scan or load to list display to detail editing so the indexed mirror still matches disk or SSH state.
