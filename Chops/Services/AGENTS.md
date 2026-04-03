# Services AGENTS.md

## Scope
- This file governs `Chops/Services/`.
- Treat this folder as the owner of scanning, parsing orchestration, store bootstrapping, remote access, registry access, ACP transport, watcher logic, and logging.

## Ownership
- Keep `SkillScanner` responsible for collecting skills, canonicalizing identity, applying SwiftData upserts, remote sync, and stale-record cleanup.
- Keep `NotesService` responsible for the notes root path, timestamped note filenames, seeded note content, and note title/excerpt extraction.
- Keep `StoreBootstrap` responsible for explicit store-path setup and legacy-store migration.
- Keep `SSHService` responsible for `/usr/bin/ssh` invocation, quoting, batching, and remote file transfer behavior.
- Keep ACP transport and session logic inside the ACP service layer. Let views consume agent state; do not move transport behavior into SwiftUI code.
- Keep `TemplateManager` and `SkillRegistry` as boundary adapters to bundled/default prompts and external registry content.
- Keep `FileWatcher` focused on watch setup and debounced invalidation callbacks.
- Keep `AppLogger` as the single place that defines log categories.
- Keep `SearchService` optional and subordinate to the current list-layer search behavior unless the app intentionally redesigns search ownership.

## Always
- Keep pure file collection off the main actor and return to the main actor only for SwiftData mutation and UI-observable state changes.
- Reuse canonical-path logic whenever scan identity, symlink merging, or plugin normalization is involved.
- Preserve the existing distinction between local/plugin records and remote records.
- Keep note metadata derived from content, not filenames: prefer the first H1-H4 heading in document order, otherwise the first non-empty line, and keep excerpt extraction aligned with that chosen title line.
- Reuse the existing shell escaping and batching strategy in `SSHService` when expanding remote behavior.
- Keep vendor-specific ACP behavior behind `BaseACPAgent` hooks and `ACPAgentFactory`, not scattered across views.
- Keep registry or template services side-effect-light; let higher layers decide how results surface in the UI.
- Preserve the current scan-file precedence inside directories: prefer `SKILL.md`, then `AGENTS.md`, then the single preferred agent/rule file when the subtree explicitly supports that fallback.
- Preserve the ignored loose-markdown allowlist for config/meta files such as `AGENTS.md`, `CLAUDE.md`, `README.md`, and `CHANGELOG.md` so scans do not turn repository docs into user skills.
- Keep `FileWatcher` debounced and main-thread-callback-based. Do not trade correctness for more frequent rescans without proving the shell still behaves well under bursty file changes.
- Keep note creation in `NotesService` deterministic: filename format `yyyy-MM-dd--HH-mm-ss` with `-1`, `-2`, and so on on collisions, and initial content seeded as `# `.
- Keep `SkillRegistry.install` sanitized-name rules and the canonical `~/.agents/skills/<name>` write path in sync with `Skill.makeGlobal()`.
- Keep ACP pending writes deferred until explicit acceptance unless bypass mode is intentionally enabled at the ACP layer.

## Never
- Never let views duplicate scanning, path-detection, remote-shell, or package-registry logic.
- Never write directly to the SwiftData store from detached tasks without re-entering the main actor.
- Never bypass `StoreBootstrap` with implicit SwiftData store locations.
- Never add new tool-scan roots in ad hoc service code when they belong in `ToolSource`, `AgentTarget`, or `ChopsSettings`.
- Never delete synthetic plugin records in generic missing-file cleanup paths; preserve their metadata through the canonical synthetic resolved-path lifecycle.

## Validation
- After editing this folder, verify the full service flow you touched: scan and dedupe behavior, remote sync, registry install, template lookup, or ACP interaction.
- If you changed scanning or store bootstrap, verify startup scan, rescan after watched-file changes, legacy-store path assumptions, and metadata retention on previously indexed records.
