import Foundation
import ACPModel

/// ACP agent for Claude Code.
///
/// Claude-specific stream classification:
/// - `agentThoughtChunk` → accumulates into `thoughtText`; shown in collapsible Thinking section.
/// - `agentMessageChunk` → accumulates raw into `responseText`; tag stripping applied at read time.
/// - `toolCall`          → activity label only; Claude does not embed diffs here.
/// - `toolCallUpdate`    → diffs captured from status-less updates; completed/failed clears activity.
@Observable
@MainActor
final class ClaudeACPAgent: BaseACPAgent {

    // MARK: - Tag Stripping

    /// Claude uses both bare and `antml:` namespaced variants of these tags.
    private static let tagsToStrip = [
        "function_calls", "invoke", "parameter", "thinking",
        "antml:function_calls", "antml:invoke", "antml:parameter"
    ]

    // MARK: - Content Hooks

    /// Thought chunks are Claude's extended-thinking / reasoning stream.
    /// Accumulated in full into `thoughtText` for display in a collapsible "Thinking" section.
    /// `currentActivity` is set to a short label so the activity row shows "Thinking…"
    /// rather than truncated reasoning mid-sentence.
    override func onThoughtChunk(_ content: ContentBlock) {
        currentActivity = "Thinking…"
        if case .text(let t) = content, !t.text.isEmpty {
            thoughtText += t.text
        }
    }

    /// Message chunks are Claude's conversational reply.
    /// Accumulated raw into `responseText` — postProcess (tag stripping) is applied at
    /// read time by `conversationalText()`, not per-chunk, to avoid splitting tags across chunks.
    override func onMessageChunk(_ content: ContentBlock) {
        if case .text(let t) = content {
            responseText += t.text
            acpLog.debug("onMessageChunk: +\(t.text.count) chars, total=\(responseText.count)")
        }
    }

    /// `toolCall` notifications from Claude carry no diff content — update activity label only.
    override func onToolCall(_ toolCall: ToolCallUpdate) {
        switch toolCall.status {
        case .completed, .failed:
            currentActivity = nil
        default:
            currentActivity = toolCall.title
        }
    }

    /// `toolCallUpdate` is Claude's primary diff delivery channel.
    ///
    /// Claude emits two distinct `tool_call_update` shapes for the `Write` tool:
    ///
    /// 1. **Status-less** — carries `content[{type:"diff", path, newText, oldText}]`.
    ///    This is the pre-write preview delivered before the file is touched on disk.
    ///    Diffs are captured here so `oldText` (or a disk read) is reliable.
    ///
    /// 2. **Status: completed/failed** — carries `rawOutput` but no diff content.
    ///    Used only to clear the activity label.
    ///
    /// `inProgress` updates carry a `title` to display while the tool is running.
    override func onToolCallUpdate(_ update: ToolCallUpdateDetails) {
        captureDiffs(from: update.content)

        guard let status = update.status else { return }
        switch status {
        case .completed, .failed:
            currentActivity = nil
            logToolResultContent(update.content)
        case .inProgress:
            if let title = update.title { currentActivity = title }
        default:
            break
        }
    }

    // MARK: - Diff Capture

    /// Extracts `ToolCallContent.diff` blocks and appends them to `pendingWrites`.
    /// Reading `oldText` here is safe — the diff block is delivered before Claude's
    /// write tool has touched the file on disk.
    private func captureDiffs(from content: [ToolCallContent]?) {
        guard let content else { return }
        for item in content {
            guard case .diff(let d) = item else { continue }
            let oldText: String? = d.oldText
                ?? (try? String(contentsOfFile: d.path, encoding: .utf8))
                ?? (try? String(contentsOfFile: d.path, encoding: .utf16))
            // Replace any existing entry for this path — Claude may emit multiple diff blocks
            // for the same file (preview then final). The last one is the most current.
            if let existing = pendingWrites.firstIndex(where: { $0.path == d.path }) {
                pendingWrites[existing] = (path: d.path, content: d.newText, original: pendingWrites[existing].original)
            } else {
                pendingWrites.append((path: d.path, content: d.newText, original: oldText))
            }
            acpLog.info("diff intercepted: \(d.path) original=\(oldText?.count ?? -1) chars (\(pendingWrites.count) total)")
        }
    }

    // MARK: - Response Post-Processing

    override func postProcess(_ text: String) -> String {
        Self.stripXMLTags(text, tags: Self.tagsToStrip)
    }

    // MARK: - Private Helpers

    private static func stripXMLTags(_ text: String, tags: [String]) -> String {
        var result = text
        for tag in tags {
            for prefix in ["</\(tag)", "<\(tag)"] {
                var i = result.startIndex
                while i < result.endIndex,
                      let open = result.range(of: prefix, range: i ..< result.endIndex),
                      let close = result.range(of: ">", range: open.lowerBound ..< result.endIndex) {
                    result.removeSubrange(open.lowerBound ... close.lowerBound)
                    i = open.lowerBound
                }
            }
        }
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func logToolResultContent(_ content: [ToolCallContent]?) {
        content?.forEach {
            if case .content(let cc) = $0, case .text(let t) = cc {
                acpLog.debug("Tool result: \(String(t.text.prefix(200)))")
            }
        }
    }
}
