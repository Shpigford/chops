import Foundation
import ACPModel

/// ACP agent for Cursor.
///
/// Cursor delivers conversational replies via `agentMessageChunk` with no XML wrapping.
/// Diffs arrive through `handleFileWriteRequest` in the base class.
@Observable
@MainActor
final class CursorACPAgent: BaseACPAgent {

    override func onThoughtChunk(_ content: ContentBlock) {}

    override func postProcess(_ text: String) -> String {
        return text.trimmingCharacters(in: .newlines)
    }
}
