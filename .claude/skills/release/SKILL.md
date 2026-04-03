---
name: release
description: Determine the next version, update the marketing site, and run the full release pipeline.
---

Cut a new release of Fast Talk. Determines the version from git history, updates the marketing site, and runs the release script.

## Instructions

### Step 1: Verify prerequisites

1. Confirm `.env` exists in the project root. If it does not, stop and tell the user:
   "Missing `.env` file. Copy `.env.example` to `.env` and fill in APPLE_TEAM_ID, APPLE_ID, and SIGNING_IDENTITY_NAME."
2. Confirm the notarytool keychain profile `AC_PASSWORD` works:
   ```bash
   xcrun notarytool history --keychain-profile "AC_PASSWORD" >/dev/null 2>&1
   ```
   If it fails, stop and tell the user to run:
   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD" --apple-id "<APPLE_ID>" --team-id "<TEAM_ID>" --password "<app-specific-password>"
   ```
3. Confirm the working tree is clean (`git status --porcelain`). If there are uncommitted changes, stop and tell the user to commit or stash first.
4. Confirm you are on the `main` branch. If not, stop and tell the user to switch to `main` first.

### Step 2: Determine the next version

1. Get the latest tag:
   ```bash
   git tag -l 'v*' | sort -V | tail -1
   ```
2. Get commits since that tag:
   ```bash
   git log <latest_tag>..HEAD --oneline --format='%s'
   ```
3. If there are zero commits since the last tag, stop and tell the user there is nothing to release.
4. Apply semver logic to the current latest version:
   - If any commit message starts with `feat:` or `feat(` → **minor** bump (e.g. 1.1.0 → 1.2.0)
   - If all commits are `fix:`, `chore:`, `docs:`, or similar → **patch** bump (e.g. 1.1.0 → 1.1.1)
   - If any commit contains `BREAKING CHANGE` or uses a `!:` suffix → ask the user what version to use
   - If the commit messages are ambiguous or do not follow conventional commits, use `mcp__conductor__AskUserQuestion` to ask:
     - question: "Commits since the last release don't clearly indicate the version bump. What version should this release be?"
     - header: "Release version"
     - multiSelect: false
     - options with labels: "Patch (X.Y.Z+1)", "Minor (X.Y+1.0)", "Major (X+1.0.0)", "Custom"

### Step 3: Confirm the version

Always confirm the version before proceeding. Use `mcp__conductor__AskUserQuestion`:
- question: "Release as v<VERSION>? Commits included:\n<commit list>"
- header: "Confirm release"
- multiSelect: false
- options:
  - "Yes, release v<VERSION>"
  - "Use a different version"
  - "Cancel"

If the user picks "Use a different version", ask them for the version number. If they pick "Cancel", stop.

### Step 3.5: Update CHANGELOG.md

1. Check if `CHANGELOG.md` has an `## [Unreleased]` section with content (bullet points).
2. If the `## [Unreleased]` section is empty or missing, draft entries from commits since the last tag:
   - **Rewrite each entry to be user-facing.** Don't echo commit messages. Describe what changed from the user's perspective — what it enables, fixes, or improves.
   - Bad: "feat: add skills registry browser with multi-agent install"
   - Good: "Browse and install community skills directly from the app"
   - Keep entries succinct (one line each). No technical jargon, no commit prefixes.
   - Confirm the drafted entries with the user using `mcp__conductor__AskUserQuestion`.
3. Rename `## [Unreleased]` to `## [VERSION] - YYYY-MM-DD` (today's date).
4. Add a new empty `## [Unreleased]` section above it.

### Step 4: Update the marketing site version

1. Edit `site/src/pages/index.astro`. Find the line containing `class="requires"` and replace it with:
   ```html
   <p class="requires">v<VERSION> &middot; Requires macOS Sequoia</p>
   ```
   where `<VERSION>` is the confirmed version.
2. Commit this change along with the changelog:
   ```bash
   git add site/src/pages/index.astro CHANGELOG.md
   git commit -m "chore: update site version to v<VERSION>"
   git push
   ```

### Step 5: Run the release script

```bash
./scripts/release.sh <VERSION>
```

This handles: xcodegen → archive → export → DMG → notarize → staple → git tag → appcast → push → GitHub Release.

Let it run to completion. If it fails, report the error output to the user and stop. Do NOT retry automatically.

### Step 6: Push and report

Ensure all commits are on the remote:
```bash
git push
```

Tell the user:
- The version that was released
- Link: `https://github.com/Shpigford/fasttalk/releases/tag/v<VERSION>`
- Remind them to deploy the marketing site if needed (`npm run build` from `site/`)

## Important Rules

- ALWAYS confirm the version with the user before proceeding
- NEVER run the release script if `.env` is missing or the working tree is dirty
- NEVER skip the marketing site version update
- If the release script fails, do NOT retry — report the error and stop
- The release script handles git tagging and GitHub release creation — do not duplicate those steps
