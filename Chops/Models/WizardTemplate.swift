import Foundation

// MARK: - Wizard Template Type

/// Types of wizard templates for AI-assisted composition
enum WizardTemplateType: String, CaseIterable, Codable, Identifiable {
    case agent = "agent"
    case skill = "skill"
    case rule = "rule"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .agent: "Agent Composer"
        case .skill: "Skill Composer"
        case .rule: "Rule Composer"
        }
    }

    var fileName: String {
        "\(rawValue)-composer.md"
    }

    var icon: String {
        switch self {
        case .agent: "person.2.fill"
        case .skill: "doc.text.fill"
        case .rule: "list.bullet.rectangle.fill"
        }
    }

    /// Map from SkillCategory
    static func from(category: SkillCategory) -> WizardTemplateType {
        switch category {
        case .agents: .agent
        case .skill: .skill
        case .rules: .rule
        }
    }
}

// MARK: - Wizard Template

/// A wizard template with content and metadata
struct WizardTemplate: Identifiable, Equatable {
    var id: String { type.rawValue }
    let type: WizardTemplateType
    var content: String
    var lastModified: Date

    /// Render template with placeholders replaced
    func render(fileContent: String, userInstructions: String) -> String {
        content
            .replacingOccurrences(of: "{{file_content}}", with: fileContent)
            .replacingOccurrences(of: "{{user_instructions}}", with: userInstructions)
    }
}
