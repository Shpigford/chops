import Foundation

/// Returns the right transport for a given agent ID. Both supported agents are driven
/// directly via the user's installed CLI.
@MainActor
enum AgentFactory {
    static func make(for agentId: AgentID) -> any AgentSession {
        switch agentId {
        case .claude: return ClaudeCLIAgent()
        case .codex:  return CodexCLIAgent()
        }
    }
}
