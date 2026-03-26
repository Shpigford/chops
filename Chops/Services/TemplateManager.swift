import Foundation

// MARK: - Template Manager

/// Manages wizard templates for AI-assisted composition
@Observable
@MainActor
final class TemplateManager {
    static let shared = TemplateManager()

    private(set) var templates: [WizardTemplate] = []

    private let fileManager = FileManager.default

    private var templatesDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Chops/templates", isDirectory: true)
    }

    private init() {
        ensureTemplatesExist()
        loadTemplates()
    }

    // MARK: - Public API

    /// Get template for a specific type
    func template(for type: WizardTemplateType) -> WizardTemplate? {
        templates.first { $0.type == type }
    }

    /// Save updated template content
    func save(_ template: WizardTemplate) {
        let url = templatesDirectory.appendingPathComponent(template.type.fileName)
        do {
            try template.content.write(to: url, atomically: true, encoding: .utf8)
            if let index = templates.firstIndex(where: { $0.type == template.type }) {
                templates[index] = WizardTemplate(
                    type: template.type,
                    content: template.content,
                    lastModified: Date()
                )
            }
        } catch {
            AppLogger.fileIO.error("Failed to save template: \(error.localizedDescription)")
        }
    }

    /// Reset a template to bundled default
    func resetToDefault(_ type: WizardTemplateType) {
        guard let bundledContent = loadBundledTemplate(type) else { return }
        let template = WizardTemplate(type: type, content: bundledContent, lastModified: Date())
        save(template)
    }

    /// Reset all templates to defaults
    func resetAllToDefaults() {
        for type in WizardTemplateType.allCases {
            resetToDefault(type)
        }
    }

    // MARK: - Private

    private func ensureTemplatesExist() {
        // Create directory if needed
        if !fileManager.fileExists(atPath: templatesDirectory.path) {
            try? fileManager.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
        }

        // Copy bundled templates if not present
        for type in WizardTemplateType.allCases {
            let destURL = templatesDirectory.appendingPathComponent(type.fileName)
            if !fileManager.fileExists(atPath: destURL.path) {
                if let content = loadBundledTemplate(type) {
                    try? content.write(to: destURL, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    private func loadTemplates() {
        templates = WizardTemplateType.allCases.compactMap { type in
            let url = templatesDirectory.appendingPathComponent(type.fileName)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            let modified = attrs?[.modificationDate] as? Date ?? Date()
            return WizardTemplate(type: type, content: content, lastModified: modified)
        }
    }

    private func loadBundledTemplate(_ type: WizardTemplateType) -> String? {
        guard let url = Bundle.main.url(
            forResource: type.rawValue + "-composer",
            withExtension: "md",
            subdirectory: "Templates"
        ) else {
            return defaultTemplateContent(for: type)
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func defaultTemplateContent(for type: WizardTemplateType) -> String {
        switch type {
        case .agent:
            return Self.defaultAgentTemplate
        case .skill:
            return Self.defaultSkillTemplate
        case .rule:
            return Self.defaultRuleTemplate
        }
    }

    // MARK: - Default Templates

    private static let defaultAgentTemplate = """
    # Agent Composer

    You are helping create or improve an AI agent definition.

    ## Context
    - File type: Agent
    - Agents define autonomous AI behaviors with specific capabilities

    ## Current Content
    {{file_content}}

    ## User Instructions
    {{user_instructions}}

    ## Guidelines
    1. Follow the agent frontmatter format (name, description, tools)
    2. Keep system prompts focused and actionable
    3. Define clear boundaries for agent behavior
    4. Include relevant tool permissions

    ## Output
    When ready, use `write_text_file` to write the complete improved content to the same file path.
    Do not show the content in a code block or ask for confirmation — write it directly.
    Do not use `str_replace` or other editing tools; always write the full file via `write_text_file`.
    """

    private static let defaultSkillTemplate = """
    # Skill Composer

    You are helping create or improve a skill definition.

    ## Context
    - File type: Skill
    - Skills are reusable knowledge/instructions for AI assistants

    ## Current Content
    {{file_content}}

    ## User Instructions
    {{user_instructions}}

    ## Guidelines
    1. Use YAML frontmatter for metadata (name, description)
    2. Write clear, actionable instructions
    3. Include examples where helpful
    4. Keep scope focused and composable

    ## Output
    When ready, use `write_text_file` to write the complete improved content to the same file path.
    Do not show the content in a code block or ask for confirmation — write it directly.
    Do not use `str_replace` or other editing tools; always write the full file via `write_text_file`.
    """

    private static let defaultRuleTemplate = """
    # Rule Composer

    You are helping create or improve a rule/guideline.

    ## Context
    - File type: Rule
    - Rules define constraints, patterns, or conventions

    ## Current Content
    {{file_content}}

    ## User Instructions
    {{user_instructions}}

    ## Guidelines
    1. Be specific and unambiguous
    2. Provide rationale for each rule
    3. Include examples of correct/incorrect usage
    4. Keep rules atomic and testable

    ## Output
    When ready, use `write_text_file` to write the complete improved content to the same file path.
    Do not show the content in a code block or ask for confirmation — write it directly.
    Do not use `str_replace` or other editing tools; always write the full file via `write_text_file`.
    """
}


