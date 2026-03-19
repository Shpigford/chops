<p align="center">
  <img src="site/public/favicon.png" width="128" height="128" alt="Chops icon" />
</p>

<h1 align="center">Chops</h1>

<p align="center">Your AI agent skills, finally organized.</p>

<p align="center">
  <a href="https://github.com/Shpigford/chops/releases/latest/download/Chops.dmg">Download</a> &middot;
  <a href="https://chops.md">Website</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="site/public/screenshot.png" width="720" alt="Chops screenshot" />
</p>

One macOS app to discover, organize, and edit coding agent skills across Claude Code, Cursor, Codex, Windsurf, and Amp. Stop digging through dotfiles.

## Features

- **Multi-tool support** — Claude Code, Cursor, Codex, Windsurf, Copilot, Aider, Amp
- **Built-in editor** — Monospaced editor with Cmd+S save, frontmatter parsing
- **Collections** — Organize skills without modifying source files
- **Real-time file watching** — FSEvents-based, instant updates on disk changes
- **Full-text search** — Search across name, description, and content
- **Create new skills** — Generates correct boilerplate per tool

## Requirements

- macOS 15 (Sequoia) or later

## Development

```bash
brew install xcodegen
xcodegen generate
open Chops.xcodeproj
```

## Architecture

- **SwiftUI** + **SwiftData** — native macOS, zero web views
- **Sparkle** — auto-updates via GitHub Releases
- **FSEvents** — file watching via DispatchSource
- **No sandbox** — direct access to dotfile directories

## License

MIT — see [LICENSE](LICENSE).

