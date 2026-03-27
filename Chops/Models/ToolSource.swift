import SwiftUI

enum ToolSource: String, Codable, CaseIterable, Identifiable {
    case agents
    case claude
    case cursor
    case windsurf
    case codex
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
        case .claude: "tool.claude".localized
        case .cursor: "tool.cursor".localized
        case .windsurf: "tool.windsurf".localized
        case .codex: "tool.codex".localized
        case .copilot: "tool.copilot".localized
        case .aider: "tool.aider".localized
        case .amp: "tool.amp".localized
        case .openclaw: "tool.openclaw".localized
        case .opencode: "tool.opencode".localized
        case .pi: "tool.pi".localized
        case .agents: "tool.global".localized
        case .antigravity: "tool.antigravity".localized
        case .claudeDesktop: "tool.claudeDesktop".localized
        case .custom: "tool.custom".localized
        }
    }

    /// SF Symbol fallback icon name
    var iconName: String {
        switch self {
        case .claude: "brain.head.profile"
        case .cursor: "cursorarrow.rays"
        case .windsurf: "wind"
        case .codex: "book.closed"
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
        case .cursor: "tool-cursor"
        case .codex: "tool-codex"
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
        case .cursor: .blue
        case .windsurf: .teal
        case .codex: .green
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
        case .cursor: return ["\(home)/.cursor/agents"]
        case .codex: return ["\(home)/.codex/agents"]
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
        case .cursor: return ["\(home)/.cursor/skills", "\(home)/.cursor/rules"]
        case .windsurf: return ["\(home)/.codeium/windsurf/memories", "\(home)/.windsurf/rules"]
        case .codex: return ["\(home)/.codex/skills"]
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
