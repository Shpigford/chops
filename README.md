<p align="center">
  <img src="site/public/favicon.png" width="128" height="128" alt="Fast Talk icon" />
</p>

<h1 align="center">Fast Talk</h1>

<p align="center">Your AI skills and agents, finally organized.</p>

<p align="center">
  <a href="https://github.com/Shpigford/fasttalk/releases/latest/download/FastTalk.dmg">Download</a> &middot;
  <a href="https://fasttalk.md">Website</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="site/public/screenshot.png" width="720" alt="Fast Talk screenshot" />
</p>

One macOS app to discover, organize, and edit coding agent skills and agents across Claude Code, Cursor, Codex, Windsurf, and Amp. Stop digging through dotfiles.

## Features

- **Multi-tool support** — Claude Code, Cursor, Codex, Windsurf, Copilot, Aider, Amp
- **Skills + Agents** — Discovers both skills and agents from each tool's directories
- **Built-in editor** — Monospaced editor with Cmd+S save, frontmatter parsing
- **Collections** — Organize skills and agents without modifying source files
- **Real-time file watching** — FSEvents-based, instant updates on disk changes
- **Full-text search** — Search across name, description, and content
- **Create new skills & agents** — Generates correct boilerplate per tool
- **Remote servers** — Connect to servers like [OpenClaw](https://openclaw.ai) to discover, browse, and install skills

## Prerequisites

- **macOS 15** (Sequoia) or later
- **Xcode** with command-line tools (`xcode-select --install`)
- **Homebrew** ([brew.sh](https://brew.sh))
- **xcodegen** — `brew install xcodegen`

Sparkle (auto-update framework) is the only external dependency and is pulled automatically by Xcode via Swift Package Manager. No manual setup needed.

## Quick Start

```bash
git clone https://github.com/Shpigford/fasttalk.git
cd fasttalk
brew install xcodegen    # skip if already installed
xcodegen generate        # generates FastTalk.xcodeproj from project.yml
open FastTalk.xcodeproj     # opens in Xcode
```

Then hit **Cmd+R** to build and run.

> **Note:** The Xcode project is generated from `project.yml`. If you change `project.yml`, re-run `xcodegen generate`. Don't edit the `.xcodeproj` directly.

### CLI build (no Xcode GUI)

```bash
xcodebuild -scheme FastTalk -configuration Debug build
```

## Project Structure

```
FastTalk/
├── App/
│   ├── FastTalkApp.swift        # @main entry — SwiftData ModelContainer + Sparkle
│   ├── AppState.swift         # @Observable singleton — filters, selection, search
│   └── ContentView.swift      # Three-column NavigationSplitView, kicks off scanning
├── Models/
│   ├── Skill.swift            # @Model — a discovered skill or agent file
│   ├── Collection.swift       # @Model — user-created skill groupings
│   └── ToolSource.swift       # Enum of supported tools, their paths and icons
├── Services/
│   ├── SkillScanner.swift     # Probes tool directories, upserts skills into SwiftData
│   ├── SkillParser.swift      # Dispatches to FrontmatterParser or MDCParser
│   ├── FileWatcher.swift      # FSEvents listener, triggers re-scan on changes
│   └── SearchService.swift    # In-memory full-text search
├── Utilities/
│   ├── FrontmatterParser.swift  # Extracts YAML frontmatter from .md files
│   └── MDCParser.swift          # Parses Cursor .mdc files
├── Views/
│   ├── Sidebar/               # Tool filters, skills/agents lists, collections
│   ├── Detail/                # Skill editor, metadata display
│   ├── Settings/              # Preferences & update UI
│   └── Shared/                # Reusable components (ToolBadge, NewSkillSheet)
├── Resources/                 # Asset catalog (tool icons, colors)
└── FastTalk.entitlements         # Disables sandbox (intentional)

project.yml          # xcodegen config — source of truth for Xcode project settings
scripts/             # Release pipeline (release.sh)
site/                # Marketing website (Astro 6)
```

## Architecture

**SwiftUI + SwiftData**, native macOS with zero web views.

### App lifecycle

1. `FastTalkApp` initializes a SwiftData `ModelContainer` (persists `Skill` and `SkillCollection`)
2. Sparkle updater starts in the background
3. `AppState` is created and injected into the SwiftUI environment
4. `ContentView` renders and calls `startScanning()`
5. `SkillScanner` probes all tool directories and upserts discovered skills
6. `FileWatcher` attaches FSEvents listeners — on any change, the scanner re-runs automatically

### Key design decisions

- **No sandbox.** The app needs unrestricted filesystem access to read dotfiles across `~/`. This is intentional and required for core functionality. The entitlements file explicitly disables the app sandbox.
- **Dedup via symlinks.** Skills are uniquely identified by their resolved symlink path. If the same file is symlinked into multiple tool directories, it shows up as one skill with multiple tool badges.
- **No test suite.** Validate changes manually — build, run, trigger the feature you changed, observe the result.

### State management

`AppState` is an `@Observable` class that holds all UI state: selected tool filter, selected skill, search text, sidebar filter mode. It's injected via `@Environment` and accessible from any view.

### UI layout

Three-column `NavigationSplitView`:
- **Sidebar** — tool filters and collections
- **List** — filtered/searched skill list
- **Detail** — skill editor (wraps `NSTextView` for native text editing with Cmd+S save)

## Supported Tools

FastTalk scans these directories for skills and agents:

| Tool | Skills | Agents |
|------|--------|--------|
| Claude Code | `~/.claude/skills/` | `~/.claude/agents/` |
| Cursor | `~/.cursor/skills/`, `~/.cursor/rules` | `~/.cursor/agents/` |
| Windsurf | `~/.codeium/windsurf/memories/`, `~/.windsurf/rules` | — |
| Codex | `~/.codex/skills/` | `~/.codex/agents/` |
| Amp | `~/.config/amp/skills/` | — |
| Global | `~/.agents/skills/` | — |

Copilot and Aider are also supported but only detect project-level skills and agents (no global paths). Custom scan paths can be added for any tool.

Tool definitions live in `FastTalk/Models/ToolSource.swift` — each enum case knows its display name, icon, color, and filesystem paths.

## Common Dev Tasks

### Add support for a new tool

1. Add a new case to the `ToolSource` enum in `FastTalk/Models/ToolSource.swift`
2. Fill in `displayName`, `iconName`, `color`, and `globalPaths`
3. Optionally add a logo to the asset catalog and return it from `logoAssetName`
4. Update `SkillScanner` if the new tool uses a non-standard file layout

### Modify skill parsing

- **Frontmatter (`.md`)** — edit `FastTalk/Utilities/FrontmatterParser.swift`
- **Cursor `.mdc` files** — edit `FastTalk/Utilities/MDCParser.swift`
- **Dispatch logic** — edit `FastTalk/Services/SkillParser.swift` (decides which parser to use)

### Change the UI

Views are in `FastTalk/Views/`, organized by column (Sidebar, Detail) and shared components. The main layout is in `FastTalk/App/ContentView.swift`.

## Testing

No automated test suite. Validate manually:

1. Build and run the app (Cmd+R)
2. Trigger the exact feature you changed
3. Observe the result — check for correct behavior and error messages
4. Test edge cases (empty states, missing directories, malformed files)

## Website

The marketing site lives in `site/` and is built with [Astro](https://astro.build/).

```bash
cd site
npm install      # first time only
npm run dev      # local dev server
npm run build    # production build → site/dist/
```

## AI Agent Setup

This repo includes a Claude Code skill at `.claude/skills/setup.md` that gives AI coding agents full context on the project — architecture, key files, and common tasks. If you're using Claude Code, it'll pick this up automatically.

## License

MIT — see [LICENSE](LICENSE).
