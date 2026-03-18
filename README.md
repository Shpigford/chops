# Chops

Your AI agent skills, finally organized.

One macOS app to discover, organize, tag, and edit coding agent skills across Claude Code, Cursor, Codex, Windsurf, Copilot, Aider, and Amp. Stop digging through dotfiles.

## Features

- **Multi-tool support** — Claude Code, Cursor, Codex, Windsurf, Copilot, Aider, Amp
- **Built-in editor** — Monospaced editor with Cmd+S save, frontmatter parsing
- **Tags & collections** — Organize skills without modifying source files
- **Real-time file watching** — FSEvents-based, instant updates on disk changes
- **Full-text search** — Search across name, description, and content
- **Create new skills** — Generates correct boilerplate per tool

## Requirements

- macOS 26 (Tahoe) or later

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
