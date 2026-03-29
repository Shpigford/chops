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
        case .allRules:
            result = result.filter { $0.itemKind == .rule }
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .tool(let tool):
            result = result.filter { $0.toolSources.contains(tool) }
            if let kind = appState.selectedKindFilter {
                result = result.filter { $0.itemKind == kind }
            }
        case .collection(let collName):
            result = result.filter { skill in
                skill.collections.contains { $0.name == collName }
            }
        case .server(let serverID):
            result = result.filter { $0.remoteServer?.id == serverID }
        case .composer:
            result = []
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
        case .allSkills: "Skills"
        case .allAgents: "Agents"
        case .allRules: "Rules"
        case .favorites: "Favorites"
        case .tool(let tool): tool.displayName
        case .collection(let name): name
        case .server(let id):
            allSkills.first(where: { $0.remoteServer?.id == id })?.remoteServer?.label ?? "Remote"
        case .composer: "Composer"
        }
    }

    /// Whether the current filter shows mixed item types (skills and agents together)
    private var showsTypeBadge: Bool {
        switch appState.sidebarFilter {
        case .allSkills, .allAgents, .allRules: false
        case .tool: appState.selectedKindFilter == nil
        default: true
        }
    }

    private var navigationSubtitle: String {
        if case .tool = appState.sidebarFilter, let kind = appState.selectedKindFilter {
            return kind.displayName
        }
        return ""
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if let kind = appState.selectedKindFilter {
            ContentUnavailableView(
                "No \(kind.displayName)",
                systemImage: kind.icon,
                description: Text("No \(kind.displayName.lowercased()) match the current filter.")
            )
        } else {
            switch appState.sidebarFilter {
            case .allAgents:
                ContentUnavailableView("No Agents", systemImage: "person.crop.rectangle",
                    description: Text("No agents match the current filter."))
            case .allRules:
                ContentUnavailableView("No Rules", systemImage: "list.bullet.rectangle",
                    description: Text("No rules match the current filter."))
            default:
                ContentUnavailableView("No Skills", systemImage: "doc.text",
                    description: Text("No skills match the current filter."))
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for skill: Skill) -> some View {
        Button(skill.isFavorite ? "Unfavorite" : "Favorite") {
            skill.isFavorite.toggle()
            try? modelContext.save()
        }
        if !allCollections.isEmpty {
            Menu("Collections") {
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
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(skill.filePath, inFileViewerRootedAtPath: "")
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            activeAlert = .confirmDelete(skill)
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
                    .contextMenu { contextMenu(for: skill) }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(navigationSubtitle)
        .toolbar {
            if case .tool = appState.sidebarFilter, appState.selectedKindFilter != nil {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.selectedKindFilter = nil
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmDelete(let skill):
                return Alert(
                    title: Text("Delete \(skill.displayTypeName)?"),
                    message: Text("This will permanently delete \"\(skill.name)\" from disk."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteSkill(skill)
                    },
                    secondaryButton: .cancel()
                )
            case .deleteError(let message):
                return Alert(
                    title: Text("Delete Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .overlay {
            if filteredSkills.isEmpty { emptyStateView }
        }
    }
}

struct SkillRow: View {
    let skill: Skill
    var showTypeBadge: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showTypeBadge {
                let kindIcon: String = switch skill.itemKind {
                case .agent: "person.crop.rectangle"
                case .rule: "list.bullet.rectangle"
                case .skill: "doc.text"
                }
                Image(systemName: kindIcon)
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
