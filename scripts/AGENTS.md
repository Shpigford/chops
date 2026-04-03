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
  - tag and push
  - generate and copy Sparkle appcast
  - commit and push appcast update
  - create GitHub release
- Keep Sparkle appcast generation aligned with `site/public/appcast.xml` and the DMG artifact produced by the script.
- Keep the notary profile contract explicit: the script expects the `AC_PASSWORD` keychain profile to exist before the release starts.
- Keep DMG styling dependent on `scripts/dmg-background.png` and the AppleScript Finder layout block unless the packaging format changes intentionally.
- Keep the Sparkle signing and appcast contract tied to the current DerivedData Sparkle binary lookup, `CHANGELOG.md`, and GitHub release URL shape.

## Always
- Keep script changes explicit and auditable; prefer clear variables and named helper functions over dense one-liners.
- Keep shell quoting strict around paths, changelog parsing, and notarization inputs.
- Preserve the repo-relative path assumptions used by the script, especially `.env`, `CHANGELOG.md`, `ExportOptions.plist`, `site/public/appcast.xml`, and `scripts/dmg-background.png`.
- Keep release output filenames and GitHub release URLs consistent with the current Sparkle feed expectations unless changing the entire release contract.
- Remember that this script mutates git state twice: once for the version tag and once for the generated appcast commit. Treat dry runs and partial reruns accordingly.

## Never
- Never reorder tagging, notarization, appcast generation, or GitHub release creation casually; those steps are intentionally coupled.
- Never turn script-side generated artifacts into hand-edited files without changing the release process itself.
- Never move app runtime logic into this folder.
- Never use the full release script as a casual validation command when a narrower shell check can prove the edit safely.

## Validation
- After editing this folder, verify the touched shell logic with the narrowest safe command, then verify that the documented release sequence still matches the script.
