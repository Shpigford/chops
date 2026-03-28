import SwiftUI

enum ToolSource: String, Codable, CaseIterable, Identifiable {
    case agents
    case claude
    case claudeInternal
    case cursor
    case windsurf
    case codex
    case codexInternal
    case codebuddy
    case copilot
    case aider
    case amp
    case openclaw
    case opencode
    case pi
    case antigravity
    case claudeDesktop
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .claudeInternal: "Claude Internal"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .codex: "Codex"
        case .codexInternal: "Codex Internal"
        case .codebuddy: "CodeBuddy"
        case .copilot: "Copilot"
        case .aider: "Aider"
        case .amp: "Amp"
        case .openclaw: "OpenClaw"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .agents: "Global"
        case .antigravity: "Antigravity"
        case .claudeDesktop: "Claude Desktop"
        case .custom: "Custom"
        }
    }

    /// SF Symbol fallback icon name
    var iconName: String {
        switch self {
        case .claude: "brain.head.profile"
        case .claudeInternal: "brain.head.profile"
        case .cursor: "cursorarrow.rays"
        case .windsurf: "wind"
        case .codex: "book.closed"
        case .codexInternal: "book.closed"
        case .codebuddy: "hammer"
        case .copilot: "airplane"
        case .aider: "wrench.and.screwdriver"
        case .amp: "bolt.fill"
        case .openclaw: "server.rack"
        case .opencode: "terminal"
        case .pi: "sparkles"
        case .agents: "globe"
        case .antigravity: "arrow.up.circle"
        case .claudeDesktop: "desktopcomputer"
        case .custom: "folder"
        }
    }

    /// Asset catalog image name, nil if no custom logo
    var logoAssetName: String? {
        switch self {
        case .claude: "tool-claude"
        case .claudeInternal: "tool-claude"
        case .cursor: "tool-cursor"
        case .codex: "tool-codex"
        case .codexInternal: "tool-codex"
        case .codebuddy: "tool-codebuddy"
        case .windsurf: "tool-windsurf"
        case .copilot: "tool-copilot"
        case .amp: "tool-amp"
        case .antigravity: "tool-antigravity"
        case .claudeDesktop: "tool-claude"
        case .opencode: "tool-opencode"
        default: nil
        }
    }

    var color: Color {
        switch self {
        case .claude: .orange
        case .claudeInternal: .brown
        case .cursor: .blue
        case .windsurf: .teal
        case .codex: .green
        case .codexInternal: .mint
        case .codebuddy: .blue
        case .copilot: .purple
        case .aider: .yellow
        case .amp: .pink
        case .openclaw: .indigo
        case .opencode: .red
        case .pi: .cyan
        case .agents: .mint
        case .antigravity: .red
        case .claudeDesktop: .orange
        case .custom: .gray
        }
    }

    var globalAgentPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claude: return ["\(home)/.claude/agents"]
        case .claudeInternal: return ["\(home)/.claude-internal/agents"]
        case .cursor: return ["\(home)/.cursor/agents"]
        case .codex: return ["\(home)/.codex/agents"]
        case .codexInternal: return ["\(home)/.codex-internal/agents"]
        case .codebuddy: return ["\(home)/.codebuddy/agents"]
        default: return []
        }
    }

    var globalPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configHome: String = {
            if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
                return xdg
            }
            return "\(home)/.config"
        }()
        switch self {
        case .claude: return ["\(home)/.claude/skills"]
        case .claudeInternal: return ["\(home)/.claude-internal/skills"]
        case .cursor: return ["\(home)/.cursor/skills", "\(home)/.cursor/rules"]
        case .windsurf: return ["\(home)/.codeium/windsurf/memories", "\(home)/.windsurf/rules"]
        case .codex: return ["\(home)/.codex/skills"]
        case .codexInternal: return ["\(home)/.codex-internal/skills"]
        case .codebuddy: return ["\(home)/.codebuddy/skills"]
        case .copilot: return ["\(home)/.copilot/skills"]
        case .aider: return []
        case .amp: return ["\(configHome)/amp/skills"]
        case .openclaw: return []
        case .opencode: return ["\(configHome)/opencode/skills"]
        case .pi: return ["\(home)/.pi/agent/skills"]
        case .agents: return ["\(home)/.agents/skills"]
        case .antigravity: return ["\(home)/.gemini/antigravity/skills"]
        case .claudeDesktop: return []
        case .custom: return []
        }
    }

    /// Whether the tool is actually installed on this machine.
    /// Checks for app bundles, CLI binaries, tool-specific config files,
    /// or known global skill locations that imply a real setup is present.
    var isInstalled: Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        switch self {
        case .claude:
            return fm.fileExists(atPath: "\(home)/.claude/settings.json")
                || fm.fileExists(atPath: "\(home)/.claude/CLAUDE.md")
                || fm.fileExists(atPath: "\(home)/.claude/plugins/installed_plugins.json")
                || Self.cliBinaryExists("claude")
        case .claudeInternal:
            return fm.fileExists(atPath: "\(home)/.claude-internal/settings.json")
                || fm.fileExists(atPath: "\(home)/.claude-internal/CLAUDE.md")
                || Self.cliBinaryExists("claude-internal")
        case .cursor:
            return fm.fileExists(atPath: "/Applications/Cursor.app")
                || fm.fileExists(atPath: "\(home)/.cursor/argv.json")
        case .windsurf:
            return fm.fileExists(atPath: "/Applications/Windsurf.app")
                || fm.fileExists(atPath: "\(home)/.codeium/windsurf/argv.json")
        case .codex:
            return fm.fileExists(atPath: "\(home)/.codex/config.toml")
                || fm.fileExists(atPath: "\(home)/.codex/auth.json")
                || Self.cliBinaryExists("codex")
        case .codexInternal:
            return fm.fileExists(atPath: "\(home)/.codex-internal/config.toml")
                || fm.fileExists(atPath: "\(home)/.codex-internal/auth.json")
                || Self.cliBinaryExists("codex-internal")
        case .codebuddy:
            return fm.fileExists(atPath: "\(home)/.codebuddy/settings.json")
                || fm.fileExists(atPath: "\(home)/.codebuddy/CODEBUDDY.md")
                || Self.cliBinaryExists("codebuddy")
        case .amp:
            let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
                .flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.config"
            return fm.fileExists(atPath: "\(configHome)/amp/config.json")
                || fm.fileExists(atPath: "\(configHome)/amp/settings.json")
                || Self.cliBinaryExists("amp")
        case .pi:
            return Self.cliBinaryExists("pi")
        case .copilot:
            return fm.fileExists(atPath: "\(home)/.copilot")
                || Self.cliBinaryExists("copilot")
        case .agents:
            return fm.fileExists(atPath: "\(home)/.agents/skills")
        case .antigravity:
            return Self.appBundleExists("Antigravity")
                || fm.fileExists(atPath: "\(home)/.gemini/antigravity/skills")
                || fm.fileExists(atPath: "\(home)/.antigravity")
                || Self.cliBinaryExists("antigravity")
        case .opencode:
            let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
                .flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.config"
            return Self.appBundleExists("OpenCode")
                || fm.fileExists(atPath: "\(configHome)/opencode/opencode.json")
                || fm.fileExists(atPath: "\(configHome)/opencode/opencode.jsonc")
                || fm.fileExists(atPath: "\(home)/.local/share/opencode")
                || Self.cliBinaryExists("opencode")
        case .claudeDesktop:
            return Self.appBundleExists("Claude")
        case .aider, .openclaw, .custom:
            return true
        }
    }

    private static func appBundleExists(_ name: String) -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let paths = [
            "/Applications/\(name).app",
            "\(home)/Applications/\(name).app",
        ]
        return paths.contains { fm.fileExists(atPath: $0) }
    }

    private static func cliBinaryExists(_ name: String) -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let paths = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "\(home)/.local/bin/\(name)",
        ]
        for path in paths where fm.fileExists(atPath: path) {
            return true
        }
        let nvmDir = "\(home)/.nvm/versions/node"
        if let nodeDirs = try? fm.contentsOfDirectory(atPath: nvmDir) {
            for nodeDir in nodeDirs {
                if fm.fileExists(atPath: "\(nvmDir)/\(nodeDir)/bin/\(name)") { return true }
            }
        }
        return false
    }
}
