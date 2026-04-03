import Foundation

/// Parser for Cursor .mdc rule files.
/// MDC files use a frontmatter-like format with YAML between --- delimiters,
/// followed by markdown content.
enum MDCParser {
    static func parse(_ text: String) -> ParsedSkill {
        // MDC files use the same frontmatter format as SKILL.md
        FrontmatterParser.parse(text)
    }
}
