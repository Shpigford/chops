import SwiftUI
import SwiftData

struct SkillListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var allSkills: [Skill]

    private var filteredSkills: [Skill] {
        var result = allSkills

        switch appState.sidebarFilter {
        case .all:
            break
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .tool(let tool):
            result = result.filter { $0.toolSources.contains(tool) }
        case .collection(let collName):
            result = result.filter { skill in
                skill.collections.contains { $0.name == collName }
            }
        }

        if !appState.searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(appState.searchText) ||
                $0.skillDescription.localizedCaseInsensitiveContains(appState.searchText) ||
                $0.content.localizedCaseInsensitiveContains(appState.searchText)
            }
        }

        return result
    }

    private var title: String {
        switch appState.sidebarFilter {
        case .all: "All Skills"
        case .favorites: "Favorites"
        case .tool(let tool): tool.displayName
        case .collection(let name): name
        }
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSkill) {
            ForEach(filteredSkills) { skill in
                SkillRow(skill: skill)
                    .tag(skill)
                    .contextMenu {
                        Button(skill.isFavorite ? "Unfavorite" : "Favorite") {
                            skill.isFavorite.toggle()
                            try? modelContext.save()
                        }
                        Divider()
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(skill.filePath, inFileViewerRootedAtPath: "")
                        }
                    }
            }
        }
        .navigationTitle(title)
        .overlay {
            if filteredSkills.isEmpty {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: "doc.text",
                    description: Text("No skills match the current filter.")
                )
            }
        }
    }
}

struct SkillRow: View {
    let skill: Skill

    var body: some View {
        HStack(spacing: 6) {
            Text(skill.name)
                .lineLimit(1)

            if skill.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            Spacer()

            if let project = skill.projectName {
                Text(project)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 3) {
                ForEach(skill.toolSources, id: \.self) { tool in
                    ToolIcon(tool: tool, size: 14)
                        .help(tool.displayName)
                        .opacity(0.6)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

