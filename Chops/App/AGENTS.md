# App AGENTS.md

## Scope
- This file governs `Chops/App/`.
- Keep this folder responsible for application entry, scene wiring, startup coordination, and shell-level UI state only.

## Ownership
- Keep `ChopsApp` responsible for `ModelContainer` creation, settings-scene injection, Sparkle updater wiring, and command registration.
- Keep `ContentView` responsible for split-view composition, startup scan orchestration, file-watcher lifecycle, and top-level sheets.
- Keep `AppState` limited to transient shell state such as selection, filters, search text, and presentation toggles.

## Always
- Inject shared shell state through `.environment(appState)` from the app entry instead of recreating app-wide state lower in the tree.
- Attach the shared SwiftData container at the scene level and let subtree views consume `modelContext` through the environment.
- Start scanner and watcher lifecycle from the shell coordinator instead of scattering startup logic across feature views.
- Add new shell-wide commands in `ChopsApp` and route them through existing notification or environment patterns when the action belongs to an already-open detail view.
- Keep sheet routing centralized in `ContentView` when the sheet is app-shell level rather than local to a single detail workflow.

## Never
- Never move filesystem scanning, remote sync, parsing, or persistence bootstrap into `AppState`.
- Never let `ChopsApp` accumulate feature-specific workflow logic that belongs in services or views.
- Never create a second startup coordinator outside `ContentView` for scan and watcher setup.
- Never store persisted domain data in `AppState`.

## Validation
- After editing this folder, verify app launch, initial scanning, sidebar/list/detail shell behavior, and any affected menu command or settings-scene wiring.
