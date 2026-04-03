# Scripts AGENTS.md

## Scope
- This file governs `scripts/`.
- Treat this folder as the owner of release and packaging automation, not feature runtime code.

## Existing Release Contract
- Keep `release.sh` as a strict Bash script with `set -euo pipefail`.
- Keep release credentials loaded from the repo-root `.env` file and fail fast when required variables are missing.
- Preserve the current high-level order:
  - read env and version
  - validate notary profile
  - generate Xcode project
  - archive and export
  - create DMG
  - notarize and staple
- Keep the script focused on private packaging output only: produce a notarized `FastTalk.dmg` and exported `FastTalk.app`, then stop.
- Keep the notary profile contract explicit: the script expects the `AC_PASSWORD` keychain profile to exist before the release starts.
- Keep DMG styling dependent on `scripts/dmg-background.png` and the AppleScript Finder layout block unless the packaging format changes intentionally.

## Always
- Keep script changes explicit and auditable; prefer clear variables and named helper functions over dense one-liners.
- Keep shell quoting strict around paths, changelog parsing, and notarization inputs.
- Preserve the repo-relative path assumptions used by the script, especially `.env`, `ExportOptions.plist`, and `scripts/dmg-background.png`.
- Keep release output filenames deterministic: `FastTalk.xcarchive`, exported `FastTalk.app`, and `FastTalk.dmg`.

## Never
- Never turn the private packaging script back into a public appcast or GitHub-release pipeline without updating this guidance and the app’s private-distribution assumptions.
- Never move app runtime logic into this folder.
- Never use the full release script as a casual validation command when a narrower shell check can prove the edit safely.

## Validation
- After editing this folder, verify the touched shell logic with the narrowest safe command, then verify that the documented release sequence still matches the script.
