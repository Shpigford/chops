import Foundation

@MainActor
final class TemplateManager {
    static let shared = TemplateManager()

    private init() {}

    /// Build a context-aware system prompt for a given template type.
    /// Substitutes `{{skill_name}}`, `{{skill_description}}`, `{{file_path}}`,
    /// `{{frontmatter}}`, and `{{kind}}` from the supplied skill context.
    func systemPrompt(
        for type: WizardTemplateType,
        skillName: String,
        skillDescription: String,
        filePath: String,
        frontmatter: [String: String]
    ) -> String {
        let base = systemPromptContent(for: type)
        let frontmatterText = frontmatter.isEmpty
            ? "(none)"
            : frontmatter.sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return base
            .replacingOccurrences(of: "{{skill_name}}", with: skillName.isEmpty ? "(unnamed)" : skillName)
            .replacingOccurrences(of: "{{skill_description}}", with: skillDescription.isEmpty ? "(no description)" : skillDescription)
            .replacingOccurrences(of: "{{file_path}}", with: filePath)
            .replacingOccurrences(of: "{{frontmatter}}", with: frontmatterText)
            .replacingOccurrences(of: "{{kind}}", with: type.rawValue)
    }

    private func systemPromptContent(for type: WizardTemplateType) -> String {
        switch type {
        case .skill: Self.defaultSkillSystemPrompt
        case .agent: Self.defaultAgentSystemPrompt
        case .rule:  Self.defaultRuleSystemPrompt
        }
    }

    private static let defaultSkillSystemPrompt = """
    You are an expert in writing skills for AI coding assistants.

    ## File you're editing
    - Name: {{skill_name}}
    - Description: {{skill_description}}
    - Path: {{file_path}}

    ## Your task
    The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

    ## Reply format (STRICT)
    Reply with two things in this exact order:
    1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble like "I'll update…").
    2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

    If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
    """

    private static let defaultAgentSystemPrompt = """
    You are an expert in writing agent definitions for AI coding assistants.

    ## File you're editing
    - Name: {{skill_name}}
    - Description: {{skill_description}}
    - Path: {{file_path}}

    ## Your task
    The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

    ## Reply format (STRICT)
    Reply with two things in this exact order:
    1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble).
    2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

    If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
    """

    private static let defaultRuleSystemPrompt = """
    You are an expert in writing rules for AI coding assistants.

    ## File you're editing
    - Name: {{skill_name}}
    - Description: {{skill_description}}
    - Path: {{file_path}}

    ## Your task
    The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

    ## Reply format (STRICT)
    Reply with two things in this exact order:
    1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble).
    2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

    If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
    """
}
