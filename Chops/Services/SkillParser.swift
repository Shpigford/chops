import Foundation

enum SkillParser {
    static func parse(fileURL: URL, toolSource: ToolSource) -> ParsedSkill? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        switch toolSource {
        case .claude, .cursor:
            if fileURL.pathExtension == "mdc" {
                return MDCParser.parse(content)
            }
            return FrontmatterParser.parse(content)
        case .codex, .amp, .windsurf, .copilot, .aider, .openclaw, .pi, .custom:
            // Try frontmatter first, fall back to heading
            let parsed = FrontmatterParser.parse(content)
            if !parsed.name.isEmpty { return parsed }
            return parseHeadingFormat(content)
        }
    }

    private static func parseHeadingFormat(_ content: String) -> ParsedSkill {
        let lines = content.components(separatedBy: "\n")
        var name = ""

        for line in lines {
            if line.hasPrefix("# ") {
                name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return ParsedSkill(
            frontmatter: [:],
            content: content,
            name: name,
            description: ""
        )
    }
}
