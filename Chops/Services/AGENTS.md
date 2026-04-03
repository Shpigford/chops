# Services AGENTS.md

## Scope
- This file governs `Chops/Services/`.
- Treat this folder as the owner of scanning, parsing orchestration, store bootstrapping, remote access, registry access, ACP transport, watcher logic, and logging.

## Ownership
- Keep `SkillScanner` responsible for collecting skills, canonicalizing identity, applying SwiftData upserts, remote sync, and stale-record cleanup.
- Keep `StoreBootstrap` responsible for explicit store-path setup and legacy-store migration.
- Keep `SSHService` responsible for `/usr/bin/ssh` invocation, quoting, batching, and remote file transfer behavior.
- Keep ACP transport and session logic inside the ACP service layer. Let views consume agent state; do not move transport behavior into SwiftUI code.
- Keep `TemplateManager` and `SkillRegistry` as boundary adapters to bundled/default prompts and external registry content.
- Keep `FileWatcher` focused on watch setup and debounced invalidation callbacks.
- Keep `AppLogger` as the single place that defines log categories.

## Always
- Keep pure file collection off the main actor and return to the main actor only for SwiftData mutation and UI-observable state changes.
- Reuse canonical-path logic whenever scan identity, symlink merging, or plugin normalization is involved.
- Preserve the existing distinction between local/plugin records and remote records.
- Reuse the existing shell escaping and batching strategy in `SSHService` when expanding remote behavior.
- Keep vendor-specific ACP behavior behind `BaseACPAgent` hooks and `ACPAgentFactory`, not scattered across views.
- Keep registry or template services side-effect-light; let higher layers decide how results surface in the UI.

## Never
- Never let views duplicate scanning, path-detection, remote-shell, or package-registry logic.
- Never write directly to the SwiftData store from detached tasks without re-entering the main actor.
- Never bypass `StoreBootstrap` with implicit SwiftData store locations.
- Never add new tool-scan roots in ad hoc service code when they belong in `ToolSource`, `AgentTarget`, or `ChopsSettings`.

## Validation
- After editing this folder, verify the full service flow you touched: scan and dedupe behavior, remote sync, registry install, template lookup, or ACP interaction.
