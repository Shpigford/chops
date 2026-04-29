import Foundation

// MARK: - Permission flow

/// One option presented to the user when an agent asks to use a tool.
/// `kind` is a stable string used by the UI to color the button (e.g. `allow_once`,
/// `allow_always`, `reject_once`, `reject_always`).
struct PermissionOption: Codable, Sendable, Identifiable {
    let kind: String
    let name: String
    let optionId: String

    var id: String { optionId }
}

/// Optional diff payload attached to a permission ask. When present the UI shows the
/// before/after content side-by-side so the user can review the proposed change before
/// clicking Allow. Required for any tool that mutates disk (Write / Edit / MultiEdit).
struct PermissionDiffPreview: Sendable {
    let path: String
    let originalText: String?
    let proposedText: String
    let existedBefore: Bool
}

/// Wraps a parked permission ask so the UI can resume it once the user clicks.
struct PermissionRequest: Identifiable, @unchecked Sendable {
    let id: UUID = UUID()
    let title: String
    let options: [PermissionOption]
    let diffPreview: PermissionDiffPreview?
    let continuation: CheckedContinuation<PermissionResponse, Error>
}

/// Result of a permission ask. `cancelled == true` means the user dismissed without choosing
/// a specific option; otherwise `optionId` identifies the chosen option.
struct PermissionResponse: Sendable {
    let optionId: String?
    let cancelled: Bool

    static func choice(_ optionId: String) -> PermissionResponse {
        PermissionResponse(optionId: optionId, cancelled: false)
    }
    static var cancelled: PermissionResponse {
        PermissionResponse(optionId: nil, cancelled: true)
    }
}

// MARK: - Activity feed

/// One step in the agent's chronological activity feed for a turn. The UI shows these
/// to give the user real-time visibility into what the agent is doing — Claude
/// generating long tool inputs can take minutes; without an activity feed it looks like
/// the app is frozen.
struct AgentActivity: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case thinking
        case toolCall(name: String)
        case toolInputDraft(name: String, charCount: Int)
        case toolResult(name: String)
        case info
    }
    enum Status: Sendable, Equatable {
        case running
        case done       // tool ran successfully (read-only / non-mutating)
        case applied    // mutating tool (Write/Edit/MultiEdit) successfully changed disk
        case failed
    }

    /// Optional rich payload so the UI can show what each step actually did when
    /// expanded. For Write/Edit this carries the diff; for Read/Bash the raw input/output.
    struct Payload: Sendable, Equatable {
        var filePath: String?
        var originalText: String?
        var proposedText: String?
        var existedBefore: Bool?
        var rawInput: String?      // pretty-printed JSON of tool input
        var resultText: String?    // tool_result content (truncated)
    }

    let id: UUID
    var kind: Kind
    var title: String
    var detail: String?
    var startedAt: Date
    var status: Status
    var payload: Payload

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        detail: String? = nil,
        startedAt: Date = Date(),
        status: Status = .running,
        payload: Payload = Payload()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.startedAt = startedAt
        self.status = status
        self.payload = payload
    }
}

// MARK: - Pending writes

/// A file write proposed by the agent. Surfaced in the chat as a diff for the user to
/// accept or reject. Both Claude (`Write` / `Edit` / `MultiEdit`) and Codex
/// (`item/fileChange/*`) populate this.
struct PendingWrite: Sendable {
    let path: String
    let content: String
    let originalText: String?
    let originalData: Data?
    let existedBefore: Bool
    /// True when the agent itself performed the disk write (the case for direct CLI
    /// agents). On reject the UI restores from the captured snapshot.
    let agentDidWrite: Bool

    init(
        path: String,
        content: String,
        originalText: String?,
        originalData: Data?,
        existedBefore: Bool,
        agentDidWrite: Bool = false
    ) {
        self.path = path
        self.content = content
        self.originalText = originalText
        self.originalData = originalData
        self.existedBefore = existedBefore
        self.agentDidWrite = agentDidWrite
    }
}

// MARK: - Errors

enum AgentError: Error, LocalizedError {
    case noSession
    case binaryNotInstalled(toolName: String, installURL: URL)
    case agentTooOld(toolName: String, found: String, minimum: String)
    case launchFailed(String)
    case processExitedDuringConnect(String)
    case connectTimedOut(stage: String)

    var errorDescription: String? {
        switch self {
        case .noSession:
            "No active agent session."
        case .binaryNotInstalled(let name, _):
            "\(name) isn't installed."
        case .agentTooOld(let name, let found, let minimum):
            "\(name) v\(found) is too old. Update to v\(minimum) or newer."
        case .launchFailed(let detail):
            "Failed to launch agent: \(detail)"
        case .processExitedDuringConnect(let detail):
            "Agent exited before initializing.\n\n\(detail)"
        case .connectTimedOut(let stage):
            "Connection timed out (\(stage))."
        }
    }
}

// MARK: - Helpers

enum AgentDataDecoding {
    /// Best-effort decode of bytes to a Swift String. Tries UTF-8 then UTF-16.
    static func text(from data: Data?) -> String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }
}
