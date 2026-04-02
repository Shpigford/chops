# Changelog

## [Unreleased]

- Add [Hermes](https://github.com/NousResearch/hermes-agent) as a tool source (`~/.hermes/skills`), including nested category folders and remote SSH paths that reference `hermes`

## [1.13.1] - 2026-03-31

- Prevents data loss when the database schema changes between versions

## [1.13.0] - 2026-03-31

- New skills default to Global and are automatically symlinked to all installed agents
- Convert any tool-specific skill to Global via the right-click menu
- Global tool source now appears in the sidebar when skills exist
- AI Assist no longer writes files until you accept the diff
- Fixed false "not installed" detection for tools using symlinked agent directories

## [1.12.0] - 2026-03-31

- Browse and install skills from OpenClaw directly on your machine
- Organize skills, rules, and agents into separate categories
- Skills inside custom scan directories are now detected correctly
- Registry browsing no longer hits GitHub API rate limits

## [1.11.0] - 2026-03-28

- Chat with AI agents directly inside Chops (ACP support)
- Cancel in-progress AI requests
- Floating AI button for quick access to the compose panel
- Improved compose panel layout and usability

## [1.10.0] - 2026-03-27

- Native markdown editor with syntax highlighting and formatting shortcuts (bold, italic, headings, links, lists)
- Select and copy text from the skill preview
- Find bar in the skill editor (Cmd+F)
- Auto-save skill files after 1 second of inactivity

## [1.9.0] - 2026-03-27

- Scan and display agents alongside skills

## [1.8.0] - 2026-03-25

- Add skills to collections via right-click context menu
- Drag and drop skills into sidebar collections
- Detect skills from Claude Desktop and CLI plugins
- Faster skill preview loading (eliminated ~2s delay)

## [1.7.0] - 2026-03-24

- Rich markdown theme in skill preview
- Support for Antigravity, OpenCode, Pi, Global Agents, and Copilot CLI as tool sources
- Sidebar hides tools that aren't installed
- Non-skill config files hidden from All Skills view
- Fixed Sparkle minimum macOS version requirement

## [1.6.0] - 2026-03-22

- Fix layout freeze when selecting a skill
- Press Enter to quickly create new collections
- Rename collections from the right-click menu

## [1.5.0] - 2026-03-21

- Connect to remote servers (such as OpenClaw) to discover, browse, and edit skills (@t2)

## [1.4.0] - 2026-03-21

- Delete skills directly from the context menu or toolbar
- Diagnostic logging and fixes for UI freezing

## [1.3.0] - 2026-03-21

- Markdown preview mode with syntax highlighting in the skill editor

## [1.2.0] - 2026-03-21

- Skills registry browser for discovering and installing community skills

## [1.1.0] - 2026-03-18

- Drag-to-Applications DMG installer with styled Finder window
- macOS Sequoia (15) support
- Credential management moved to `.env` file (no more hardcoded values)

## [1.0.1] - 2026-03-16

- About tab in settings with version info, update checks, and links
- Apple logo in download button, version and system requirements on site
- Download button links directly to DMG

## [1.0.0] - 2026-03-15

- Initial release — discover, organize, and edit AI agent skills
- Three-column layout with sidebar, skill list, and markdown editor
- Support for Claude Code, Cursor, Codex, Windsurf, Copilot, Aider, Amp
- Sparkle auto-updates with EdDSA signing
- Marketing site at chops.md
