---
name: setup
description: Get a new developer up and running with the Chops codebase — prerequisites, build, architecture, and common tasks.
---

Set up the Chops development environment and orient a new contributor to the codebase.

## Instructions

### Step 1: Check prerequisites

Verify these are installed. If any are missing, tell the user what to install and stop.

1. **macOS 15+** — `sw_vers -productVersion` (must be ≥ 15.0)
2. **Xcode CLI tools** — `xcode-select -p` (if missing: `xcode-select --install`)
3. **Homebrew** — `which brew` (if missing: direct them to https://brew.sh)
4. **xcodegen** — `which xcodegen` (if missing: `brew install xcodegen`)

### Step 2: Generate Xcode project

```bash
xcodegen generate
```

This reads `project.yml` (the source of truth for all Xcode project settings) and generates `Chops.xcodeproj`. Re-run this anytime `project.yml` changes. Never edit the `.xcodeproj` directly.

### Step 3: Build and run

```bash
xcodebuild -scheme Chops -configuration Debug build
```

Or open in Xcode and hit Cmd+R:

```bash
open Chops.xcodeproj
```

### Step 4: Orient the developer

Share this architecture overview:

**Entry point:** `Chops/App/ChopsApp.swift` — sets up SwiftData ModelContainer (Skill + SkillCollection), starts Sparkle updater, injects AppState into environment.

**State:** `Chops/App/AppState.swift` — `@Observable` singleton holding UI state (selected tool, selected skill, search text, sidebar filter).

**Models (SwiftData):**
- `Chops/Models/Skill.swift` — a discovered skill file, uniquely identified by resolved symlink path
- `Chops/Models/Collection.swift` — user-created groupings of skills
- `Chops/Models/ToolSource.swift` — enum of supported tools with display names, icons, colors, and filesystem paths

**Services:**
- `Chops/Services/SkillScanner.swift` — probes tool directories, parses frontmatter, upserts into SwiftData. Deduplicates via resolved symlink paths.
- `Chops/Services/FileWatcher.swift` — FSEvents via DispatchSource, triggers re-scan on file changes
- `Chops/Services/SkillParser.swift` — dispatches to FrontmatterParser (.md) or MDCParser (.mdc)
- `Chops/Services/SearchService.swift` — in-memory full-text search

**Views:** Three-column NavigationSplitView (Sidebar → List → Detail). Editor wraps NSTextView for native text editing. Cmd+S save via FocusedValues.

**Key design decisions:**
- No sandbox — the app needs unrestricted filesystem access to read dotfiles across ~/
- Symlink dedup — same file in multiple tool dirs shows as one skill with multiple tool badges
- No test suite — validate manually by building, running, and observing

**Scanned tool paths:**

| Tool | Paths |
|------|-------|
| Claude Code | `~/.claude/skills/`, `~/.agents/skills` |
| Cursor | `~/.cursor/skills/`, `~/.cursor/rules` |
| Windsurf | `~/.codeium/windsurf/memories/`, `~/.windsurf/rules` |
| Codex | `~/.codex` |
| Amp | `~/.config/amp` |

Copilot and Aider detect project-level skills only (no global paths).

## Common tasks to be aware of

**Add a new tool:** Add a case to `ToolSource` enum in `Chops/Models/ToolSource.swift`. Fill in `displayName`, `iconName`, `color`, `globalPaths`. Update `SkillScanner` if the tool uses a non-standard file layout.

**Modify parsing:** Frontmatter → `Chops/Utilities/FrontmatterParser.swift`. Cursor .mdc → `Chops/Utilities/MDCParser.swift`. Dispatch logic → `Chops/Services/SkillParser.swift`.

**Change UI:** Views are in `Chops/Views/` (Sidebar/, Detail/, Settings/, Shared/). Main layout is `Chops/App/ContentView.swift`.

## Important Rules

- `project.yml` is the source of truth for Xcode settings — never edit `.xcodeproj` directly
- Sparkle (auto-updates) is the only external dependency — pulled automatically via SPM
- There is no test suite — always validate changes by building and running the app manually
- The app runs without sandbox — this is intentional and required
