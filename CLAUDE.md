# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Chops

A native macOS app (SwiftUI + SwiftData) for discovering, organizing, and editing AI coding agent skills across tools (Claude Code, Cursor, Codex, Windsurf, Copilot, Aider, Amp). Fully open source (MIT), public repo at github.com/Shpigford/chops. No sandbox — requires full filesystem access to read user dotfiles.

## Build & Run

```bash
# Generate Xcode project (required after changing project.yml)
xcodegen generate

# Open in Xcode
open Chops.xcodeproj

# CLI build
xcodebuild -scheme Chops -configuration Release

# Local release-like build that launches cleanly from shell
xcodebuild -scheme Chops -configuration LocalRelease

# Release (needs APPLE_TEAM_ID, APPLE_ID, SIGNING_IDENTITY_NAME env vars)
./scripts/release.sh <version>
```

Requires: Xcode, `brew install xcodegen`, macOS 15+. Sparkle (>= 2.6.0) is the only external dependency (auto-updates via GitHub Releases).

No test suite exists. Validate manually by building and running.

## Development Rules

**Always manually test.** After every change, build the app (`xcodebuild`), launch it, and exercise the feature you changed. Seeing "build succeeded" is not enough — open the app and verify the actual behavior. If it's a UI change, look at it. If it's a data change, confirm the data. No exceptions.

**No fallbacks.** Do not write fallback logic, graceful degradation, or backwards-compatibility shims. The product should work correctly via the primary code path. If something fails, fix the root cause — don't paper over it with a fallback. We are early-stage; the code should be clean and direct, not defensive.

## Architecture

**Entry:** `Chops/App/ChopsApp.swift` → sets up SwiftData ModelContainer + Sparkle updater.
SwiftData store path is explicit: `~/Library/Application Support/Chops/Chops.store`. Do not rely on the implicit `default.store`.

**State:** `AppState` is an `@Observable` singleton holding UI filters, search text, and selection state.

**Models (SwiftData):**
- `Skill` — a discovered skill file. Uniquely identified by resolved symlink path. Tracks which tools it's installed in.
- `SkillCollection` — user-created groupings of skills (pure user data, not filesystem-backed — data loss is permanent).

**Schema versioning:** SwiftData models use `VersionedSchema` + `SchemaMigrationPlan` (see `SchemaVersions.swift`). Each schema version must declare its own nested `@Model` snapshots; app code reaches the current version through top-level `typealias`es like `Skill = SchemaV1.Skill`. When adding or changing a stored property, freeze the previous schema in place, add a new schema version (e.g. `SchemaV2`) with its own nested models, move the typealiases to the new version, and add the corresponding `MigrationStage`. Never point an older schema version at live top-level models — future migrations will crash with duplicate checksums.

**Services:**
- `SkillScanner` — probes tool directories (~/.claude/skills/, ~/.cursor/rules/, etc.), parses frontmatter, upserts into SwiftData. Deduplicates via resolved symlink paths.
- `FileWatcher` — FSEvents via `DispatchSourceFileSystemObject`, triggers re-scan on changes.
- `SkillParser` → dispatches to `FrontmatterParser` (.md) or `MDCParser` (.mdc).
- **ACP agent hierarchy** — `BaseACPAgent` owns all transport/session logic. Vendor subclasses override three hooks:
  - `shouldFilter(JsonRpcMessage) → Bool` — drop messages before SDK decoding (e.g. Augment's `usage_update`)
  - `postProcess(String) → String` — strip vendor-specific XML tags before text is stored
  - `resolvePermission(title, options)` — present permission UI; hook for future session-wide allow-all
  - `ACPAgentFactory.make(for: ToolSource)` instantiates the right subclass; `ComposePanel` holds `BaseACPAgent?`.

**Views:** Three-column `NavigationSplitView` (Sidebar → List → Detail). Editor uses native `NSTextView` with markdown highlighting. Cmd+S save via `FocusedValues`. Agent responses render via `MarkdownMessageView` (MarkdownUI `.gitHub` theme + syntax highlighting).

**Tool sources** are defined in `ToolSource.swift` — each enum case knows its display name, icon, and filesystem paths to scan.

## Release Pipeline

`scripts/release.sh` does: xcodegen → archive → export with Developer ID → create DMG → notarize → staple → git tag → generate Sparkle appcast.xml → GitHub Release. Appcast served at chops.md/appcast.xml.

## Website

Marketing site lives in `site/` — Astro 6, built with `npm run build` from that directory. Appcast XML is in `site/public/appcast.xml`.
