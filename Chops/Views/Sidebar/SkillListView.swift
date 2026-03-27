import SwiftUI
import SwiftData

struct SkillListView: View {
    private enum ActiveAlert: Identifiable {
        case confirmDelete(Skill)
        case deleteError(String)

        var id: String {
            switch self {
            case .confirmDelete(let skill):
                return "confirm-delete-\(skill.filePath)"
            case .deleteError(let message):
                return "delete-error-\(message)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \SkillCollection.name) private var allCollections: [SkillCollection]
    @State private var activeAlert: ActiveAlert?

    private var filteredSkills: [Skill] {
        var result = allSkills

        switch appState.sidebarFilter {
        case .allSkills:
            result = result.filter { $0.itemKind == .skill }
        case .allAgents:
            result = result.filter { $0.itemKind == .agent }
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .tool(let tool):
            result = result.filter { $0.toolSources.contains(tool) }
        case .collection(let collName):
            result = result.filter { skill in
                skill.collections.contains { $0.name == collName }
            }
        case .server(let serverID):
            result = result.filter { $0.remoteServer?.id == serverID }
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
        case .allSkills: "sidebar.allSkills".localized
        case .allAgents: "sidebar.allAgents".localized
        case .favorites: "sidebar.favorites".localized
        case .tool(let tool): tool.displayName
        case .collection(let name): name
        case .server(let id):
            allSkills.first(where: { $0.remoteServer?.id == id })?.remoteServer?.label ?? "common.remote".localized
        }
    }

    /// Whether the current filter shows mixed item types (skills and agents together)
    private var showsTypeBadge: Bool {
        switch appState.sidebarFilter {
        case .allSkills, .allAgents: false
        default: true
        }
    }

    private func deleteSkill(_ skill: Skill) {
        do {
            try skill.deleteFromDisk()
            if appState.selectedSkill == skill {
                appState.selectedSkill = nil
            }
            modelContext.delete(skill)
            try modelContext.save()
        } catch {
            activeAlert = .deleteError(error.localizedDescription)
        }
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSkill) {
            ForEach(filteredSkills) { skill in
                SkillRow(skill: skill, showTypeBadge: showsTypeBadge)
                    .tag(skill)
                    .draggable(skill.resolvedPath)
                    .contextMenu {
                        Button(skill.isFavorite ? "skillList.unfavorite".localized : "skillList.favorite".localized) {
                            skill.isFavorite.toggle()
                            try? modelContext.save()
                        }
                        if !allCollections.isEmpty {
                            Menu("skillList.collections".localized) {
                                ForEach(allCollections) { collection in
                                    let isAssigned = skill.collections.contains(where: { $0.name == collection.name })
                                    Button {
                                        if isAssigned {
                                            skill.collections.removeAll { $0.name == collection.name }
                                        } else {
                                            skill.collections.append(collection)
                                        }
                                        try? modelContext.save()
                                    } label: {
                                        Toggle(isOn: .constant(isAssigned)) {
                                            Label(collection.name, systemImage: collection.icon)
                                        }
                                    }
                                }
                            }
                        }
                        if !skill.isRemote {
                            Divider()
                            Button("skillList.showInFinder".localized) {
                                NSWorkspace.shared.selectFile(skill.filePath, inFileViewerRootedAtPath: "")
                            }
                        }
                        Divider()
                        Button("skillList.delete".localized, role: .destructive) {
                            activeAlert = .confirmDelete(skill)
                        }
                    }
            }
        }
        .navigationTitle(title)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmDelete(let skill):
                return Alert(
                    title: Text("skillList.deleteConfirmTitle".localized(skill.displayTypeName)),
                    message: Text("skillList.deleteConfirmMessage".localized(skill.name)),
                    primaryButton: .destructive(Text("skillList.delete".localized)) {
                        deleteSkill(skill)
                    },
                    secondaryButton: .cancel()
                )
            case .deleteError(let message):
                return Alert(
                    title: Text("skillList.deleteFailedTitle".localized),
                    message: Text(message),
                    dismissButton: .default(Text("skillList.ok".localized))
                )
            }
        }
        .overlay {
            if filteredSkills.isEmpty {
                ContentUnavailableView(
                    appState.sidebarFilter == .allAgents ? "skillList.noAgents".localized : "skillList.noSkills".localized,
                    systemImage: appState.sidebarFilter == .allAgents ? "person.crop.rectangle" : "doc.text",
                    description: Text(appState.sidebarFilter == .allAgents
                        ? "skillList.noAgentsMatch".localized
                        : "skillList.noSkillsMatch".localized)
                )
            }
        }
    }
}

struct SkillRow: View {
    let skill: Skill
    var showTypeBadge: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showTypeBadge {
                Image(systemName: skill.itemKind == .agent ? "person.crop.rectangle" : "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(skill.name)
                .lineLimit(1)

            if skill.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            Spacer()

            if skill.isRemote, let serverLabel = skill.remoteServer?.label {
                Text(serverLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if let project = skill.projectName {
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
