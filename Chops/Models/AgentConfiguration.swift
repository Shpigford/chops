import Foundation

/// Stable identifier for the supported coding agents. Currently just Claude Code and
/// Codex — both driven directly by spawning the user's installed binary.
enum AgentID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex:  "Codex"
        }
    }

    var description: String {
        switch self {
        case .claude: "Anthropic's Claude Code, driven via a one-shot `claude --print` invocation."
        case .codex:  "OpenAI Codex, driven via a one-shot `codex exec` invocation."
        }
    }

    /// Where the user can install the binary if it isn't already on disk.
    var installURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai/download")!
        case .codex:  URL(string: "https://github.com/openai/codex/releases")!
        }
    }

    /// `ToolSource` we look at to detect the binary on disk.
    var toolSource: ToolSource {
        switch self {
        case .claude: .claude
        case .codex:  .codex
        }
    }
}

/// Tracks which agents the user has enabled. The list of *supported* agents is fixed.
@Observable
@MainActor
final class AgentConfiguration {
    static let shared = AgentConfiguration()

    private static let enabledIdsKey = "agentEnabledIds"

    /// Currently-supported agents, in display order.
    let supported: [AgentID] = AgentID.allCases

    private(set) var enabledIds: Set<AgentID> {
        didSet {
            UserDefaults.standard.set(enabledIds.map(\.rawValue), forKey: Self.enabledIdsKey)
        }
    }

    var enabledAgents: [AgentID] { supported.filter { enabledIds.contains($0) } }
    var hasAnyEnabled: Bool { !enabledIds.isEmpty }

    private init() {
        let defaults = UserDefaults.standard
        // Treat "key has never been written" as first run. We do NOT use empty-array as a
        // signal, since the user might explicitly disable everything.
        let hasStoredValue = defaults.object(forKey: Self.enabledIdsKey) != nil
        let stored = defaults.stringArray(forKey: Self.enabledIdsKey) ?? []
        let migrated = Set(stored.compactMap { raw -> AgentID? in
            // Migrate legacy values from the previous registry-driven scheme.
            switch raw {
            case "claude-acp", "claude": return .claude
            case "codex-acp",  "codex":  return .codex
            default: return nil
            }
        })

        if hasStoredValue {
            self.enabledIds = migrated
        } else {
            // First run: auto-enable every supported agent whose binary we can detect on disk.
            // Saves the user from a no-op trip to Settings just to flip toggles for tools they
            // already have installed.
            var initial = Set<AgentID>()
            for id in AgentID.allCases where id.toolSource.cliBinaryURL != nil {
                initial.insert(id)
            }
            self.enabledIds = initial
            defaults.set(initial.map(\.rawValue), forKey: Self.enabledIdsKey)
        }
    }

    func isEnabled(_ id: AgentID) -> Bool { enabledIds.contains(id) }

    func setEnabled(_ id: AgentID, _ on: Bool) {
        if on { enabledIds.insert(id) } else { enabledIds.remove(id) }
    }
}
