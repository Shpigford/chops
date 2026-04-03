# AGENTS.md

## Start Here
- Read this file first, then read the nearest nested `AGENTS.md` before editing code in that subtree.
- Prefix every shell command with `rtk`.
- Commit every discrete unit of work immediately with a descriptive message that names the area changed.
- Start unfamiliar exploration with semantic/codebase search when available; use `rg` for exact follow-up lookups.

## Build And Validation
- Run `rtk xcodegen generate` after every `project.yml` edit. Install `xcodegen` first if it is missing.
- Use `rtk open FastTalk.xcodeproj` when you need to validate or inspect the app in Xcode.
- Use `rtk xcodebuild -project FastTalk.xcodeproj -scheme FastTalk -configuration LocalRelease build` for local validation outside Xcode.
- Use `rtk xcodebuild -project FastTalk.xcodeproj -scheme FastTalk -configuration Release build` before release-pipeline changes.
- Use `rtk ./scripts/release.sh <version>` only for the full signed/notarized release flow. Follow `scripts/AGENTS.md` before changing that pipeline.
- Treat manual validation as required. No automated test suite exists in this repo.
- After UI or workflow changes, launch the app and exercise the changed flow; a green build alone is not enough.

## Critical Boundaries
- Treat filesystem and SSH-backed content as the source of truth. Treat SwiftData as the indexed mirror used for browsing, grouping, and editing.
- Keep `Skill.resolvedPath` stable across local symlinks, plugin installs, and remote records. Treat it as the identity boundary for dedupe and metadata retention.
- Keep persisted model evolution behind new `SchemaV*` snapshots and migration-plan updates. Never mutate an older schema snapshot in place.
- Keep `FastTalkApp` focused on scene wiring, model-container setup, commands, and updater integration.
- Keep `ContentView` as the shell coordinator for startup scanning, file watching, split-view composition, and sheet routing.
- Prefer native macOS SwiftUI patterns and local AppKit bridges over custom cross-platform abstractions.

## Change Routing
- Use `FastTalk/AGENTS.md` for all app code.
- Use `scripts/AGENTS.md` for release automation or packaging changes.
- Treat `site/public/appcast.xml` as release output owned by the release script, not as a hand-edited marketing file.

## Never
- Never add a second source-of-truth layer for files already backed by disk or SSH state.
- Never hardcode tool paths, install-detection rules, or scan roots outside the registries and services that already own them.
- Never replace the existing compact native macOS UI language with bespoke styling unless the closest subtree instructions explicitly require it.
- Never leave the repo without a commit once a discrete implementation unit is complete.
