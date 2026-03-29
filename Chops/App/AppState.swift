import SwiftUI

@Observable
final class AppState {
    var selectedTool: ToolSource?
    var selectedSkill: Skill?
    var searchText: String = ""
    var showingNewSkillSheet: Bool = false
    var showingRegistrySheet: Bool = false
    var newItemKind: ItemKind = .skill
    var sidebarFilter: SidebarFilter = .allSkills
    /// Set when user drills into a specific kind within a tool filter. Nil shows the kind picker.
    var selectedKindFilter: ItemKind?
    /// Set when user picks a template type from ComposerPickerView.
    var selectedTemplateType: WizardTemplateType?
}

enum SidebarFilter: Hashable {
    case allSkills
    case allAgents
    case allRules
    case favorites
    case tool(ToolSource)
    case collection(String)
    case server(String)
    case composer
}
