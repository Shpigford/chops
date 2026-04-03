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
    /// Filter by item kind within a tool view (nil = show all)
    var toolKindFilter: ItemKind?
}

enum SidebarFilter: Hashable {
    case allNotes
    case allSkills
    case allAgents
    case allRules
    case favorites
    case tool(ToolSource)
    case collection(String)
    case server(String)
}
