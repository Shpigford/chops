import SwiftUI

@Observable
final class AppState {
    var selectedTool: ToolSource?
    var selectedSkill: Skill?
    var selectedSkillPaths: Set<String> = []
    var searchText: String = ""
    var showingNewSkillSheet: Bool = false
    var showingRegistrySheet: Bool = false
    var newItemKind: ItemKind = .skill
    var sidebarFilter: SidebarFilter = .allSkills
    /// Filter by item kind within a tool view (nil = show all)
    var toolKindFilter: ItemKind?

    var hasMultipleSelection: Bool {
        selectedSkillPaths.count > 1
    }

    func selectOnly(_ skill: Skill?) {
        guard let skill else {
            selectedSkillPaths = []
            selectedSkill = nil
            return
        }

        selectedSkillPaths = [skill.resolvedPath]
        selectedSkill = skill
    }

    func setListSelection(_ selection: Set<String>, availableSkills: [Skill]) {
        selectedSkillPaths = selection
        syncSelectedSkill(using: availableSkills)
    }

    func repairSelection(in availableSkills: [Skill], autoSelectFirst: Bool = true) {
        let availablePaths = Set(availableSkills.map(\.resolvedPath))
        let retainedSelection = selectedSkillPaths.intersection(availablePaths)

        if retainedSelection != selectedSkillPaths {
            selectedSkillPaths = retainedSelection
        }

        syncSelectedSkill(using: availableSkills)

        if autoSelectFirst, selectedSkillPaths.isEmpty, let firstSkill = availableSkills.first {
            selectOnly(firstSkill)
        } else if selectedSkillPaths.isEmpty {
            selectedSkill = nil
        }
    }

    private func syncSelectedSkill(using availableSkills: [Skill]) {
        guard selectedSkillPaths.count == 1, let selectedPath = selectedSkillPaths.first else {
            selectedSkill = nil
            return
        }

        selectedSkill = availableSkills.first(where: { $0.resolvedPath == selectedPath })
    }
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
