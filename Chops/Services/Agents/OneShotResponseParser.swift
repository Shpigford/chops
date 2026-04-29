import Foundation

/// Shared parser for one-shot agent replies. Both Claude (`claude -p --output-format json`)
/// and Codex (`codex exec --output-last-message`) ask the model for "summary + fenced full
/// file" or a structured edits JSON envelope; this turns either into `(summary, newContent)`.
enum OneShotResponseParser {

    /// `summary` is plain text the user sees in chat. `newContent` is the proposed file
    /// body — `nil` means the agent replied conversationally with no edit to apply.
    struct Result {
        let summary: String
        let newContent: String?
    }

    /// Decoded shape of the structured-edits JSON format.
    private struct EditsResponse: Decodable {
        let summary: String
        let edits: [EditOp]

        struct EditOp: Decodable {
            let find: String
            let replace: String
        }
    }

    static func parse(_ text: String, originalContent: String?) -> Result {
        // 1. Try structured-edits JSON first.
        let stripped = stripCodeFences(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = stripped.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(EditsResponse.self, from: data) {
            if parsed.edits.isEmpty {
                return Result(summary: parsed.summary, newContent: nil)
            }
            if let original = originalContent,
               let applied = try? applyEdits(parsed.edits, to: original) {
                return Result(summary: parsed.summary, newContent: applied)
            }
            return Result(summary: parsed.summary, newContent: nil)
        }

        // 2. Fall back to summary + fenced full-file block.
        guard let openingRange = openingFenceRange(in: text) else {
            return Result(
                summary: text.trimmingCharacters(in: .whitespacesAndNewlines),
                newContent: nil
            )
        }
        let summary = String(text[..<openingRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterOpening = String(text[openingRange.upperBound...])
        if let closingRange = lastClosingFenceRange(in: afterOpening) {
            return Result(
                summary: summary,
                newContent: String(afterOpening[..<closingRange.lowerBound])
            )
        }
        return Result(summary: summary, newContent: String(afterOpening))
    }

    // MARK: - Internals

    private static func openingFenceRange(in text: String) -> Range<String.Index>? {
        // ``` at start-of-string or after a newline, optional language hint, then newline.
        let pattern = #"(?m)^```[a-zA-Z0-9_-]*\n"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let match = regex.rangeOfFirstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        guard match.location != NSNotFound,
              let r = Range(match, in: text) else { return nil }
        return r
    }

    private static func lastClosingFenceRange(in text: String) -> Range<String.Index>? {
        // Use the last fence line as the wrapper close so Markdown files containing their
        // own fenced examples do not get truncated at the first inner code block.
        let pattern = #"(?m)^```\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last,
              let r = Range(last.range, in: text) else { return nil }
        return r
    }

    private static func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["```json\n", "```JSON\n", "```\n"]
        for prefix in prefixes where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
        if s.hasSuffix("\n```") { s.removeLast(4) }
        else if s.hasSuffix("```") { s.removeLast(3) }
        return s
    }

    private static func applyEdits(_ edits: [EditsResponse.EditOp], to original: String) throws -> String {
        var content = original
        for (i, edit) in edits.enumerated() {
            var occurrences = 0
            var searchStart = content.startIndex
            while let r = content.range(of: edit.find, range: searchStart..<content.endIndex) {
                occurrences += 1
                searchStart = r.upperBound
                if occurrences > 1 { break }
            }
            switch occurrences {
            case 0:
                throw AgentError.launchFailed(
                    "Edit #\(i + 1): the `find` text doesn't appear in the file. Proposed:\n\n\(edit.find.prefix(300))"
                )
            case 1:
                if let r = content.range(of: edit.find) {
                    content.replaceSubrange(r, with: edit.replace)
                }
            default:
                throw AgentError.launchFailed(
                    "Edit #\(i + 1): the `find` text appears more than once — needs more surrounding context to be unique."
                )
            }
        }
        return content
    }
}

/// Small helpers shared by one-shot agents for assembling the system + user prompts.
enum OneShotPrompts {
    /// System prompt sent to the agent when the host hasn't supplied one. Identical for
    /// Claude and Codex so the parser can rely on a consistent reply format.
    static func defaultSystemPrompt(filePath: String?) -> String {
        let name = filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "the file"
        return """
        You are helping the user edit \(name) — a Markdown file used to instruct an AI coding assistant.

        Apply the user's request **minimally**. Preserve every unchanged line exactly — same whitespace, same blank lines, same wording. Do not refactor or "improve" anything the user didn't ask about.

        ## Reply format

        Reply with two things in this exact order:
        1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble).
        2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

        If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
        """
    }

    /// Wraps the user's request with the current file content so the agent has full context
    /// without needing tool access.
    static func userMessage(userRequest: String, filePath: String?, fileContent: String?) -> String {
        var parts: [String] = []
        if let filePath, let fileContent {
            let name = URL(fileURLWithPath: filePath).lastPathComponent
            parts.append("Current contents of \(name):")
            parts.append("```")
            parts.append(fileContent.isEmpty ? "(empty file)" : fileContent)
            parts.append("```")
            parts.append("")
        }
        parts.append("User's request:")
        parts.append(userRequest)
        return parts.joined(separator: "\n")
    }
}
