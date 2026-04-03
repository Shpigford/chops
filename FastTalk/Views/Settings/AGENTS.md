# Settings Views AGENTS.md

## Scope
- This file governs `FastTalk/Views/Settings/`.
- Treat this subtree as the owner of the settings scene shell and feature-specific preferences panes.

## Shell Rules
- Keep `SettingsView` as the single tabbed settings container.
- Add new settings as a dedicated pane or a clear extension of an existing pane; do not scatter settings UI across unrelated views.
- Keep panes self-sizing and compact. Follow the existing fixed-width preferences window style.

## Existing Patterns To Preserve
- Use `@AppStorage` for small preference values that do not justify a heavier persistence layer.
- Use notifications only when a setting invalidates app-wide runtime state, as `customScanPathsChanged` already does.
- Keep settings copy concise and operational; explain what changes, not product marketing.
- Use grouped forms, compact buttons, and secondary explanatory text instead of custom settings chrome.
- Keep subsystem settings narrow:
  - library settings for scan/plugin behavior
  - AI assist settings for ACP registry and templates
  - server settings for SSH-backed sources
  - about tab for updater and metadata
- Keep scan-affecting controls posting `.customScanPathsChanged` from this subtree so the shell rescan path stays centralized.

## Integration Rules
- Reuse existing save and invalidation pathways when a setting affects scanning, registry availability, or assistant behavior.
- Keep remote-server management and ACP configuration inside this subtree instead of surfacing them as ad hoc dialogs elsewhere in the app.
- When a setting changes runtime behavior, make that coupling explicit in the code and in the control label or helper text.
- Keep updater, diagnostics export, remote connection testing, and assistant template editing attached to the settings scene rather than leaking them into unrelated workflows.

## Never
- Never add long-running service logic directly to settings containers when it belongs in a service or a focused row/sheet component.
- Never invent a second settings shell outside `SettingsView`.
- Never store scan-affecting settings in local view state only.

## Validation
- After editing this subtree, verify the affected pane in the settings window and then verify the runtime behavior that the setting is meant to control.
