---
name: release
description: Determine the next version, update the marketing site, and run the full release pipeline.
---

Cut a new release of Chops. Determines the version from git history, updates the marketing site, and runs the release script.

## Instructions

### Step 1: Verify prerequisites

1. Confirm `.env` exists in the project root. If it does not, stop and tell the user:
   "Missing `.env` file. Copy `.env.example` to `.env` and fill in APPLE_TEAM_ID, APPLE_ID, and SIGNING_IDENTITY_NAME."
2. Confirm the working tree is clean (`git status --porcelain`). If there are uncommitted changes, stop and tell the user to commit or stash first.
3. Confirm you are on the `main` branch. If not, stop and tell the user to switch to `main` first.

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

### Step 4: Update the marketing site version

1. Edit `site/src/pages/index.astro`. Find the line containing `class="requires"` and replace it with:
   ```html
   <p class="requires">v<VERSION> &middot; Requires macOS Sequoia</p>
   ```
   where `<VERSION>` is the confirmed version.
2. Commit this change:
   ```bash
   git add site/src/pages/index.astro
   git commit -m "chore: update site version to v<VERSION>"
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
- Link: `https://github.com/Shpigford/chops/releases/tag/v<VERSION>`
- Remind them to deploy the marketing site if needed (`npm run build` from `site/`)

## Important Rules

- ALWAYS confirm the version with the user before proceeding
- NEVER run the release script if `.env` is missing or the working tree is dirty
- NEVER skip the marketing site version update
- If the release script fails, do NOT retry — report the error and stop
- The release script handles git tagging and GitHub release creation — do not duplicate those steps
