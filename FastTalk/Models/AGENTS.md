# Models AGENTS.md

## Scope
- This file governs `FastTalk/Models/`.
- Treat this folder as the home for persisted schema snapshots, model semantics, small configuration registries, and enum-based source-of-truth lookups.

## Persistence Rules
- Add persisted fields only by creating a new schema version in `SchemaVersions.swift`, moving the top-level typealiases forward, and updating `FastTalkMigrationPlan`.
- Keep each historical `SchemaV*` snapshot frozen once released. Never retrofit new stored properties into an older snapshot.
- Keep `resolvedPath` unique and stable. Any change that weakens its deduplication role must be deliberate and repository-wide.
- Keep remote identity encoded as `remote://<server-id>/<remote-path>` and local plugin identities encoded through the existing synthetic prefixes. Do not replace them with unstable raw filesystem paths.
- Keep relationship behavior explicit. `RemoteServer.skills` uses cascade deletion and collection membership is persisted user data.

## Model Semantics
- Keep computed behavior in extensions when it derives from stored state and is reused across views and services.
- Keep `Skill` as the place for install-path merging, deletion-target resolution, read-only checks, trash semantics, and global-skill promotion helpers.
- Keep `ToolSource` and `AgentTarget` authoritative for display names, icon mapping, install evidence, and filesystem path registries.
- Keep `FastTalkSettings` limited to lightweight user-default backed settings and derived source-of-truth paths.
- Keep `ACPConfiguration` focused on ACP registry filtering, enabled-agent persistence, and agent resolution.
- Keep `WizardTemplateType` and related types aligned with the assistant-composer flows that already consume them.
- Keep storage encodings hidden behind computed accessors: `toolSourcesRaw` remains comma-separated, `installedPathsData` remains JSON, and `frontmatterData` remains JSON.
- Keep `Skill.isReadOnly`, `Skill.isPlugin`, and `Skill.canMakeGlobal` aligned with the filesystem and plugin semantics already enforced elsewhere in the app.
- Keep local note identity split correctly: fixed timestamp filename on disk, stable `resolvedPath` in SwiftData, and content-derived display name in the UI.

## Always
- Encode collections such as `toolSources`, `installedPaths`, and `frontmatter` in one place and expose typed computed accessors instead of leaking raw storage shapes into views.
- Prefer derived helpers that preserve existing behavior over call-site duplication in views and services.
- Add new tool integrations by extending the existing registries, not by hardcoding paths or labels in arbitrary call sites.
- Keep `makeGlobal()` and registry installs centered on the canonical `~/.agents/skills/<name>` directory and let symlink fan-out derive from `AgentTarget`.
- Keep local deletes reversible by moving files to Trash and snapshotting enough metadata to restore favorites, collections, kind, installed paths, and resolved-path identity through undo.

## Never
- Never move SwiftData schema definitions out of `SchemaVersions.swift`.
- Never treat `Collection.swift` or `RemoteServer.swift` as independent model definitions when the real stored snapshots live inside the versioned schema.
- Never duplicate install-detection or global-path logic outside `ToolSource` or `AgentTarget`.
- Never write callers against `toolSourcesRaw`, `installedPathsData`, or `frontmatterData` directly.

## Validation
- After editing this folder, verify schema compilation, scan identity behavior, collection membership behavior, and any UI surfaces that rely on tool labels, icons, or counts.
- If identity or install semantics changed, verify dedupe, make-global, delete, and remote-server sync behavior against existing indexed records.
