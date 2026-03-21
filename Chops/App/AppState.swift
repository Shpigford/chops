import SwiftUI

@Observable
final class AppState {
    var selectedTool: ToolSource?
    var selectedSkill: Skill?
    var searchText: String = ""
    var showingNewSkillSheet: Bool = false
    var showingRegistrySheet: Bool = false
    var sidebarFilter: SidebarFilter = .all
}

enum SidebarFilter: Hashable {
    case all
    case favorites
    case tool(ToolSource)
    case collection(String)
}
