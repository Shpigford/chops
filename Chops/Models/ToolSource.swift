import SwiftUI

enum ToolSource: String, Codable, CaseIterable, Identifiable {
    case agents
    case augment
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

    /// Whether this tool should appear in the sidebar tools list.
    var listable: Bool {
        switch self {
        case .custom, .claudeDesktop, .agents, .aider:
            return false
        default:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .augment: "Auggie"
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .codex: "Codex"
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
        case .augment: "wand.and.sparkles"
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
        case .augment: "tool-augment"
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
        case .augment: .cyan
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
        case .augment: return ["\(home)/.augment/skills"]
        case .claude: return ["\(home)/.claude/skills"]
        case .cursor: return ["\(home)/.cursor/skills"]
        case .windsurf: return []
        case .codex: return ["\(home)/.codex/skills"]
        case .copilot: return ["\(home)/.copilot/skills"]
        case .aider: return []
        case .amp: return ["\(configHome)/amp/skills"]
        case .openclaw:
            var paths: [String] = []
            // Main skills directory
            if FileManager.default.fileExists(atPath: "\(home)/.openclaw/skills") {
                paths.append("\(home)/.openclaw/skills")
            }
            // Workspace skills (search all workspace dirs)
            let openclawDir = URL(fileURLWithPath: "\(home)/.openclaw")
            if let workspaces = try? FileManager.default.contentsOfDirectory(
                at: openclawDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for workspace in workspaces {
                    let skillsPath = workspace.appendingPathComponent("skills")
                    if FileManager.default.fileExists(atPath: skillsPath.path) {
                        paths.append(skillsPath.path)
                    }
                }
            }
            // NPM global installation (ARM Mac)
            if FileManager.default.fileExists(atPath: "/opt/homebrew/lib/node_modules/openclaw/skills") {
                paths.append("/opt/homebrew/lib/node_modules/openclaw/skills")
            }
            // NPM global installation (Intel Mac)
            if FileManager.default.fileExists(atPath: "/usr/local/lib/node_modules/openclaw/skills") {
                paths.append("/usr/local/lib/node_modules/openclaw/skills")
            }
            return paths
        case .opencode: return ["\(configHome)/opencode/skills"]
        case .pi: return ["\(home)/.pi/agent/skills"]
        case .agents: return ["\(home)/.agents/skills"]
        case .antigravity: return ["\(home)/.gemini/antigravity/skills"]
        case .claudeDesktop: return []
        case .custom: return []
        }
    }

    var globalRulePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .cursor: return ["\(home)/.cursor/rules"]
        case .windsurf: return ["\(home)/.codeium/windsurf/memories", "\(home)/.windsurf/rules"]
        default: return []
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
        case .augment:
            return Self.appBundleExists("Augment")
                || fm.fileExists(atPath: "\(home)/.augment/settings.json")
                || Self.cliBinaryExists("augment")
        case .claudeDesktop:
            return Self.appBundleExists("Claude")
        case .openclaw:
            return fm.fileExists(atPath: "\(home)/.openclaw")
                || Self.cliBinaryExists("openclaw")
                || fm.fileExists(atPath: "/opt/homebrew/lib/node_modules/openclaw")
                || fm.fileExists(atPath: "/usr/local/lib/node_modules/openclaw")
        case .aider, .custom:
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

    var mcpConfigPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claude:
            return ["\(home)/.claude.json"]
        case .claudeDesktop:
            return ["\(home)/Library/Application Support/Claude/claude_desktop_config.json"]
        case .cursor:
            return ["\(home)/.cursor/mcp.json"]
        case .copilot:
            return ["\(home)/.vscode/mcp.json"]
        default:
            return []
        }
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
