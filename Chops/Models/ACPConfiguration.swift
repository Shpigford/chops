import Foundation
import ACPRegistry

// MARK: - ACP Configuration Manager

/// Manages registry-based ACP agent discovery, selection, and installation.
@Observable
@MainActor
final class ACPConfiguration {
    static let shared = ACPConfiguration()

    private static let enabledIdsKey = "acpEnabledAgentIds"

    /// Allowlist of registry agent IDs surfaced in the UI.
    /// Extend this set to support additional agents.
    static let supportedAgentIds: Set<String> = [
        "claude-acp",
        "auggie",
        "codex-acp",
        "cursor"
    ]

    private let registryClient = RegistryClient()
    private let installer = AgentInstaller()

    // MARK: - Observable State

    /// Registry agents filtered to `supportedAgentIds`, in allowlist order.
    private(set) var registryAgents: [RegistryAgent] = []
    private(set) var isLoadingRegistry = false
    private(set) var registryError: String?

    private var enabledIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(enabledIds), forKey: Self.enabledIdsKey)
        }
    }

    // MARK: - Derived

    var enabledAgents: [RegistryAgent] {
        registryAgents.filter { enabledIds.contains($0.id) }
    }

    var hasEnabledACP: Bool { !enabledAgents.isEmpty }

    // MARK: - Init

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.enabledIdsKey) ?? []
        enabledIds = Set(stored)
    }

    // MARK: - Enable / Disable

    func isEnabled(_ agentId: String) -> Bool { enabledIds.contains(agentId) }

    func setEnabled(_ agentId: String, _ on: Bool) {
        if on { enabledIds.insert(agentId) } else { enabledIds.remove(agentId) }
    }

    // MARK: - Registry

    func loadRegistryIfNeeded() async {
        guard registryAgents.isEmpty, !isLoadingRegistry else { return }
        await refreshRegistry()
    }

    func refreshRegistry() async {
        isLoadingRegistry = true
        registryError = nil
        do {
            let registry = try await registryClient.fetch(forceRefresh: true)
            let allowed = Self.supportedAgentIds
            let order: [String] = ["claude-acp", "auggie", "codex-acp", "cursor"]
            registryAgents = order.compactMap { id in
                registry.agents.first { $0.id == id && allowed.contains($0.id) }
            }
        } catch {
            registryError = error.localizedDescription
        }
        isLoadingRegistry = false
    }

    // MARK: - Resolve

    /// Returns a ready-to-launch `InstalledAgent` for the given registry agent.
    /// For npx/uvx agents this is instant; for binary agents it downloads on first use.
    func resolve(_ agent: RegistryAgent) async throws -> InstalledAgent {
        if let existing = await installer.installedAgent(agent.id) {
            return existing
        }
        return try await installer.install(agent)
    }
}
