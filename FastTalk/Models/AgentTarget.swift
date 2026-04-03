import Foundation

struct AgentTarget: Identifiable, Hashable {
    let id: String
    let displayName: String
    let globalSkillsDir: String
    let skillFileName: String

    /// Paths to check — at least one must exist for the agent to be considered installed.
    /// These should be files/dirs that the actual tool creates, NOT dirs that `npx skills add` would create.
    let evidencePaths: [String]

    /// Optional: app bundle name to check in /Applications
    let appBundleName: String?

    /// Optional: CLI binary name to check in PATH
    let cliBinaryName: String?

    var isInstalled: Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Check for app bundle
        if let app = appBundleName {
            let appPaths = [
                "/Applications/\(app).app",
                "\(home)/Applications/\(app).app",
            ]
            if appPaths.contains(where: { fm.fileExists(atPath: $0) }) {
                return true
            }
        }

        // Check for CLI binary
        if let cli = cliBinaryName {
            let searchPaths = [
                "/usr/local/bin/\(cli)",
                "/opt/homebrew/bin/\(cli)",
                "\(home)/.local/bin/\(cli)",
            ]
            // Also check nvm paths
            let nvmDir = "\(home)/.nvm/versions/node"
            if let nodeDirs = try? fm.contentsOfDirectory(atPath: nvmDir) {
                for nodeDir in nodeDirs {
                    let binPath = "\(nvmDir)/\(nodeDir)/bin/\(cli)"
                    if fm.fileExists(atPath: binPath) { return true }
                }
            }
            for path in searchPaths where fm.fileExists(atPath: path) {
                return true
            }
        }

        // Check evidence paths — tool-specific config files
        for path in evidencePaths where fm.fileExists(atPath: path) {
            return true
        }

        return false
    }

    var expandedSkillsDir: String {
        (globalSkillsDir as NSString).expandingTildeInPath
    }

    static var installed: [AgentTarget] {
        all.filter(\.isInstalled)
    }

    static let all: [AgentTarget] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configHome: String = {
            if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
                return xdg
            }
            return "\(home)/.config"
        }()

        return [
            // CLI tools — detect via binary or config files
            AgentTarget(
                id: "claude-code",
                displayName: "Claude Code",
                globalSkillsDir: "\(home)/.claude/skills",
                skillFileName: "SKILL.md",
                evidencePaths: [
                    "\(home)/.claude/settings.json",
                    "\(home)/.claude/CLAUDE.md",
                    "\(home)/.claude/cache",
                ],
                appBundleName: nil,
                cliBinaryName: "claude"
            ),
            AgentTarget(
                id: "codex",
                displayName: "Codex",
                globalSkillsDir: "\(home)/.codex/skills",
                skillFileName: "SKILL.md",
                evidencePaths: [
                    "\(home)/.codex/config.toml",
                    "\(home)/.codex/auth.json",
                ],
                appBundleName: nil,
                cliBinaryName: "codex"
            ),
            AgentTarget(
                id: "amp",
                displayName: "Amp",
                globalSkillsDir: "\(configHome)/amp/skills",
                skillFileName: "SKILL.md",
                evidencePaths: [
                    "\(configHome)/amp/config.json",
                    "\(configHome)/amp/settings.json",
                ],
                appBundleName: nil,
                cliBinaryName: "amp"
            ),
            AgentTarget(
                id: "opencode",
                displayName: "OpenCode",
                globalSkillsDir: "\(configHome)/opencode/skills",
                skillFileName: "SKILL.md",
                evidencePaths: [
                    "\(configHome)/opencode/opencode.json",
                    "\(configHome)/opencode/opencode.jsonc",
                    "\(home)/.local/share/opencode",
                ],
                appBundleName: "OpenCode",
                cliBinaryName: "opencode"
            ),
            AgentTarget(
                id: "goose",
                displayName: "Goose",
                globalSkillsDir: "\(configHome)/goose/skills",
                skillFileName: "SKILL.md",
                evidencePaths: [
                    "\(configHome)/goose/config.yaml",
                    "\(configHome)/goose/profiles",
                ],
                appBundleName: nil,
                cliBinaryName: "goose"
            ),

            // IDE/editor apps — detect via /Applications
            AgentTarget(
                id: "cursor",
                displayName: "Cursor",
                globalSkillsDir: "\(home)/.cursor/skills",
                skillFileName: "SKILL.md",
                evidencePaths: [
                    "\(home)/.cursor/argv.json",
                    "\(home)/.cursor/extensions",
                ],
                appBundleName: "Cursor",
                cliBinaryName: nil
            ),
            AgentTarget(
                id: "windsurf",
                displayName: "Windsurf",
                globalSkillsDir: "\(home)/.codeium/windsurf/skills",
                skillFileName: "SKILL.md",
                evidencePaths: [
                    "\(home)/.codeium/windsurf/argv.json",
                    "\(home)/.codeium/windsurf/extensions",
                ],
                appBundleName: "Windsurf",
                cliBinaryName: nil
            ),
            AgentTarget(
                id: "warp",
                displayName: "Warp",
                globalSkillsDir: "\(home)/.warp/skills",
                skillFileName: "SKILL.md",
                evidencePaths: [
                    "\(home)/.warp/launch_configurations",
                ],
                appBundleName: "Warp",
                cliBinaryName: nil
            ),
        ]
    }()
}
