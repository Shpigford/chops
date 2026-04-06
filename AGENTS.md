# AGENTS.md

## Start Here
- Read this file first, then read the nearest nested `AGENTS.md` before editing code in that subtree.
- Prefix every shell command with `rtk`.
- Finish every discrete unit of work by validating it, then commit immediately with a descriptive message that names the area changed.
- Start unfamiliar exploration with semantic/codebase search when available; use `rg` for exact follow-up lookups.

## Build And Validation
- Prefer the `Makefile` entrypoints for end-to-end validation and deployment workflows instead of retyping the script commands by hand.
- After any repo change, run the narrowest appropriate `rtk make` target before declaring the task done.
- Use `rtk make macbook` as the default finish-line validation for app changes.
- Use `rtk make macbook` when the task includes remote deployment, remote launch, or explicit “run it on the MacBook” verification.
- Use `rtk make restart-on-macbook` only when the bundle is already copied and you only need to stop and relaunch the remote app.
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
- Keep `FastTalkApp` focused on scene wiring, model-container setup, diagnostics commands, and shell-level command registration.
- Keep `ContentView` as the shell coordinator for startup scanning, file watching, split-view composition, and sheet routing.
- Prefer native macOS SwiftUI patterns and local AppKit bridges over custom cross-platform abstractions.

## Change Routing
- Use `FastTalk/AGENTS.md` for all app code.
- Use `scripts/AGENTS.md` for release automation or packaging changes.

## Never
- Never add a second source-of-truth layer for files already backed by disk or SSH state.
- Never hardcode tool paths, install-detection rules, or scan roots outside the registries and services that already own them.
- Never replace the existing compact native macOS UI language with bespoke styling unless the closest subtree instructions explicitly require it.
- Never leave the repo without a commit once a discrete implementation unit is complete.
- Never skip the final `make` validation step for a repo change and still call the task finished.
