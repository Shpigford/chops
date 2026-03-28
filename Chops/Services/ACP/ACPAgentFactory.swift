import Foundation

/// Returns the vendor-specific agent for a given registry agent ID.
/// Maps known agent IDs to their subclass; unknown agents use the base class.
@MainActor
enum ACPAgentFactory {
    static func make(for agentId: String) -> BaseACPAgent {
        switch agentId {
        case "claude-acp": return ClaudeACPAgent()
        case "cursor":     return CursorACPAgent()
        case "auggie":     return BaseACPAgent()
        default:           return BaseACPAgent()
        }
    }
}
