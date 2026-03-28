import Foundation

// MARK: - Wizard Template Type

/// Types of wizard templates for AI-assisted composition
enum WizardTemplateType: String, CaseIterable, Codable, Identifiable {
    case skill = "skill"

    var id: String { rawValue }

    var displayName: String {
        "Skill Composer"
    }

    var fileName: String {
        "\(rawValue)-composer.md"
    }

    var icon: String {
        "doc.text.fill"
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
