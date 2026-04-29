import Foundation
import Observation

/// Transport-agnostic surface that `ComposePanel` observes. Implemented by:
/// - `ClaudeCLIAgent` — one-shot `claude --print` against the user's installed binary
/// - `CodexCLIAgent` — one-shot `codex exec` against the user's installed binary
///
/// All conformers must be `@Observable` so SwiftUI tracks property reads through the existential.
@MainActor
protocol AgentSession: AnyObject, Observable {
    var responseText: String { get }
    var thoughtText: String { get }
    var currentActivity: String? { get }
    var pendingWrites: [PendingWrite] { get }
    var deferredContent: [String: String] { get }
    var pendingPermissionRequest: PermissionRequest? { get }
    var isConnected: Bool { get }
    var isConnecting: Bool { get }
    var isProcessing: Bool { get }
    /// When non-nil, the timestamp at which the in-flight turn started. UIs use it to
    /// render an elapsed-time hint so the user can tell long thinks from hangs.
    var turnStartedAt: Date? { get }
    /// Chronological feed of what the agent has done during the current turn. Reset on
    /// each new prompt. Drives the live activity panel in the chat UI.
    var activities: [AgentActivity] { get }
    var lastError: String? { get }
    var isBypassMode: Bool { get }

    func startConnect(workingDirectory: URL, systemPrompt: String?)
    func disconnect() async

    func prompt(_ text: String) async throws
    func cancelPrompt()

    func respondToPermission(optionId: String?)
    func clearPendingWrites()
    func primeDeferredContent(for path: String, content: String)

    /// Strip vendor-specific tags / formatting before display. Default returns text unchanged.
    func conversationalText(from text: String) -> String
}
