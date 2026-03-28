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
        Self.defaultSkillSystemPrompt
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
        if !fileManager.fileExists(atPath: templatesDirectory.path) {
            try? fileManager.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
        }

        // Write bundled templates on first run; overwrite outdated stored versions.
        for type in WizardTemplateType.allCases {
            let destURL = templatesDirectory.appendingPathComponent(type.fileName)
            guard let bundled = loadBundledTemplate(type) else { continue }

            if !fileManager.fileExists(atPath: destURL.path) {
                try? bundled.write(to: destURL, atomically: true, encoding: .utf8)
            } else if let stored = try? String(contentsOf: destURL, encoding: .utf8),
                      templateNeedsUpdate(stored: stored, bundled: bundled) {
                try? bundled.write(to: destURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Returns true when a stored template's version marker is older than the bundled version.
    /// Only auto-updates templates that still carry the default version header — user-customized
    /// templates that omit the marker are left untouched.
    private func templateNeedsUpdate(stored: String, bundled: String) -> Bool {
        guard let storedVersion = extractVersion(from: stored),
              let bundledVersion = extractVersion(from: bundled) else {
            return false
        }
        return storedVersion < bundledVersion
    }

    private func extractVersion(from content: String) -> Int? {
        let prefix = "<!-- chops-template-version: "
        guard let start = content.range(of: prefix),
              let end = content.range(of: " -->", range: start.upperBound ..< content.endIndex) else {
            return nil
        }
        return Int(content[start.upperBound ..< end.lowerBound])
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
        Self.defaultSkillTemplate
    }

    // MARK: - Default Templates

    private static let defaultSkillTemplate = """
    <!-- chops-template-version: 2 -->
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
    """


    // MARK: - Default System Prompts

    private static let defaultSkillSystemPrompt = """
    You are an expert in writing skills for AI coding assistants that use the Model Context Protocol (MCP).

    ## Current skill context
    - Name: {{skill_name}}
    - Description: {{skill_description}}
    - File: {{file_path}}
    - Frontmatter:
    {{frontmatter}}

    ## Your role
    When the user asks you to create or update this skill, use the ACP `write_text_file` tool to write the complete updated file content directly to the file path shown above.
    Do not show the content in a code block or ask for confirmation — write it directly via `write_text_file`.
    Always write the full file, including YAML frontmatter.
    """

}


