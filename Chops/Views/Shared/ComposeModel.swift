import Foundation

// MARK: - Chat Model

enum ChatRole { case user, assistant }

enum DiffStatus: Sendable { case pending, accepted, rejected }

struct ChatDiff: Sendable {
    let path: String
    /// Pre-edit content. `nil` means the file did not exist before the agent wrote it.
    let original: String?
    let originalData: Data?
    let existedBefore: Bool
    let proposed: String
    /// True when the agent already performed the disk write (e.g. Claude direct CLI). On
    /// reject we must restore from `originalData`.
    let agentDidWrite: Bool
    var status: DiffStatus = .pending

    init(
        path: String,
        original: String?,
        originalData: Data?,
        existedBefore: Bool,
        proposed: String,
        agentDidWrite: Bool = false,
        status: DiffStatus = .pending
    ) {
        self.path = path
        self.original = original
        self.originalData = originalData
        self.existedBefore = existedBefore
        self.proposed = proposed
        self.agentDidWrite = agentDidWrite
        self.status = status
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var text: String
    var thoughtText: String
    var isError: Bool
    var diffs: [ChatDiff]

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        thoughtText: String = "",
        isError: Bool = false,
        diffs: [ChatDiff] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thoughtText = thoughtText
        self.isError = isError
        self.diffs = diffs
    }
}

// MARK: - Layout Constants

enum ComposeConstants {
    static let defaultPanelHeight: CGFloat = 400
    static let bubbleWidthRatio: CGFloat = 0.80
}
