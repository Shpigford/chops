# App AGENTS.md

## Scope
- This file governs `FastTalk/App/`.
- Keep this folder responsible for application entry, scene wiring, startup coordination, and shell-level UI state only.

## Ownership
- Keep `FastTalkApp` responsible for `ModelContainer` creation, settings-scene injection, diagnostics command wiring, and command registration.
- Keep `ContentView` responsible for split-view composition, startup scan orchestration, file-watcher lifecycle, and top-level sheets.
- Keep `AppState` limited to transient shell state such as selection, filters, search text, and presentation toggles.
- Keep `AppState.selectedSkillPaths` as the source of truth for middle-list selection and treat `selectedSkill` as the derived single-detail selection only.

## Always
- Inject shared shell state through `.environment(appState)` from the app entry instead of recreating app-wide state lower in the tree.
- Attach the shared SwiftData container at the scene level and let subtree views consume `modelContext` through the environment.
- Start scanner and watcher lifecycle from the shell coordinator instead of scattering startup logic across feature views.
- Add new shell-wide commands in `FastTalkApp` and route them through existing notification or environment patterns when the action belongs to an already-open detail view.
- Keep the File > New command mapped to direct note creation only when the Notes library filter is active. Reuse the same `newNoteRequested` path as the Notes `+` button instead of inventing a second creation flow.
- Keep sheet routing centralized in `ContentView` when the sheet is app-shell level rather than local to a single detail workflow.
- Keep scan/watch roots centralized in `ContentView`: derive standard roots from `ToolSource` registries and append one-off Claude plugin/session paths there rather than spreading watchers across features.
- Keep `ContentView` empty-state copy aligned with the current filter and with multi-selection. Multiple selected items should clear the detail pane rather than showing a synthetic multi-edit surface.
- Reuse `.customScanPathsChanged` when settings or installs should trigger a full rescan.

## Never
- Never move filesystem scanning, remote sync, parsing, or persistence bootstrap into `AppState`.
- Never let `FastTalkApp` accumulate feature-specific workflow logic that belongs in services or views.
- Never create a second startup coordinator outside `ContentView` for scan and watcher setup.
- Never store persisted domain data in `AppState`.
- Never move shell search, split-view selection fallback, or top-level empty-state behavior into a lower subtree that cannot see the full navigation context.

## Validation
- After editing this folder, verify app launch, initial scanning, sidebar/list/detail shell behavior, and any affected menu command or settings-scene wiring.
- If watch roots or startup flow changed, verify that file edits, installs, and scan-path setting changes all trigger rescans once the app is already running.
