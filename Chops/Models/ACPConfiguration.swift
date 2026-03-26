import Foundation
import SwiftUI

// MARK: - ACP Tool Configuration

/// Configuration for a single ACP-compatible tool
struct ACPToolConfig: Codable, Identifiable, Equatable {
    var id: String { tool.rawValue }
    let tool: ToolSource
    var enabled: Bool
    var binaryPath: String
    var flags: String

    /// Check if binary exists and is executable
    var isValid: Bool {
        guard enabled, !binaryPath.isEmpty else { return false }
        let expanded = (binaryPath as NSString).expandingTildeInPath
        return FileManager.default.isExecutableFile(atPath: expanded)
    }

    /// Expanded binary path (resolves ~)
    var expandedBinaryPath: String {
        (binaryPath as NSString).expandingTildeInPath
    }

    static func defaultConfig(for tool: ToolSource) -> ACPToolConfig {
        ACPToolConfig(
            tool: tool,
            enabled: false,
            binaryPath: tool.defaultACPBinaryHint,
            flags: "--stdio"
        )
    }
}

// MARK: - ACP Configuration Manager

/// Manages ACP configurations for all supported tools
@Observable
@MainActor
final class ACPConfiguration {
    static let shared = ACPConfiguration()

    /// Supported ACP tools
    static let supportedTools: [ToolSource] = [.augment, .claude, .cursor]

    private let configsKey = "acpToolConfigs"

    /// All tool configurations
    var configs: [ACPToolConfig] {
        didSet { save() }
    }

    private init() {
        configs = Self.load() ?? Self.defaultConfigs()
    }

    // MARK: - Accessors

    /// Get config for a specific tool
    func config(for tool: ToolSource) -> ACPToolConfig? {
        configs.first { $0.tool == tool }
    }

    /// Get all enabled and valid tools
    var enabledTools: [ToolSource] {
        configs.filter(\.isValid).map(\.tool)
    }

    /// Check if any ACP is available
    var hasEnabledACP: Bool {
        !enabledTools.isEmpty
    }

    // MARK: - Mutators

    /// Update config for a tool
    func updateConfig(_ config: ACPToolConfig) {
        if let index = configs.firstIndex(where: { $0.tool == config.tool }) {
            configs[index] = config
        }
    }

    /// Reset all configs to defaults
    func resetToDefaults() {
        configs = Self.defaultConfigs()
    }

    // MARK: - Persistence

    private static func defaultConfigs() -> [ACPToolConfig] {
        supportedTools.map { ACPToolConfig.defaultConfig(for: $0) }
    }

    private static func load() -> [ACPToolConfig]? {
        guard let data = UserDefaults.standard.data(forKey: "acpToolConfigs"),
              let decoded = try? JSONDecoder().decode([ACPToolConfig].self, from: data) else {
            return nil
        }
        // Ensure all supported tools have a config
        var configs = decoded
        for tool in supportedTools where !configs.contains(where: { $0.tool == tool }) {
            configs.append(ACPToolConfig.defaultConfig(for: tool))
        }
        return configs
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: configsKey)
    }
}

// MARK: - ToolSource ACP Extensions

extension ToolSource {
    /// Default binary path hint for ACP tools
    var defaultACPBinaryHint: String {
        switch self {
        case .augment: return "~/.augment/bin/augment"
        case .claude: return "~/.claude/local/claude"
        case .cursor: return ""
        default: return ""
        }
    }

    /// Whether this tool supports ACP
    var supportsACP: Bool {
        ACPConfiguration.supportedTools.contains(self)
    }
}
