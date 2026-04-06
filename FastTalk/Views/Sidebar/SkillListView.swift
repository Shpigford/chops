import SwiftUI
import SwiftData

struct SkillListView: View {
    private enum ActiveAlert: Identifiable {
        case createNoteError(String)
        case confirmMakeGlobal(Skill)
        case deleteError(String)
        case makeGlobalError(String)

        var id: String {
            switch self {
            case .createNoteError(let message):
                return "create-note-error-\(message)"
            case .confirmMakeGlobal(let skill):
                return "confirm-make-global-\(skill.filePath)"
            case .deleteError(let message):
                return "delete-error-\(message)"
            case .makeGlobalError(let message):
                return "make-global-error-\(message)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \SkillCollection.name) private var allCollections: [SkillCollection]
    @State private var activeAlert: ActiveAlert?

    private var filteredSkills: [Skill] {
        var result = allSkills

        switch appState.sidebarFilter {
        case .allNotes:
            result = result.filter { $0.itemKind == .note }
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
            if let kind = appState.toolKindFilter {
                result = result.filter { $0.itemKind == kind }
            }
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

        if case .allNotes = appState.sidebarFilter {
            result.sort { $0.fileModifiedDate > $1.fileModifiedDate }
        }

        return result
    }

    private var title: String {
        switch appState.sidebarFilter {
        case .allNotes: "Notes"
        case .allSkills: "Skills"
        case .allAgents: "Agents"
        case .allRules: "Rules"
        case .favorites: "Favorites"
        case .tool(let tool): tool.displayName
        case .collection(let name): name
        case .server(let id):
            allSkills.first(where: { $0.remoteServer?.id == id })?.remoteServer?.label ?? "Remote"
        }
    }

    /// Whether the current filter shows mixed item types (skills and agents together)
    private var showsTypeBadge: Bool {
        switch appState.sidebarFilter {
        case .allNotes, .allSkills, .allAgents, .allRules: false
        case .tool: appState.toolKindFilter == nil
        default: true
        }
    }

    private var availableKinds: [ItemKind] {
        guard case .tool(let tool) = appState.sidebarFilter else { return [] }
        let kinds = Set(allSkills.filter { $0.toolSources.contains(tool) }.map(\.itemKind))
        return ItemKind.allCases.filter { kinds.contains($0) }
    }

    private var filteredSkillPaths: [String] {
        filteredSkills.map(\.resolvedPath)
    }

    private var selectedSkills: [Skill] {
        filteredSkills.filter { appState.selectedSkillPaths.contains($0.resolvedPath) }
    }

    private var selectionBinding: Binding<Set<String>> {
        Binding(
            get: { appState.selectedSkillPaths },
            set: { appState.setListSelection($0, availableSkills: filteredSkills) }
        )
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if let kind = appState.toolKindFilter {
            ContentUnavailableView(
                "No \(kind.displayName)",
                systemImage: kind.icon,
                description: Text("No \(kind.displayName.lowercased()) match the current filter.")
            )
        } else {
            switch appState.sidebarFilter {
            case .allNotes:
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "note.text",
                    description: Text("Use the + button to create your first note.")
                )
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

    private var isNotesLibraryView: Bool {
        if case .allNotes = appState.sidebarFilter {
            return true
        }
        return false
    }

    @ViewBuilder
    private func contextMenu(for skill: Skill) -> some View {
        Button(skill.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            skill.isFavorite.toggle()
            try? modelContext.save()
        }
        if skill.canMakeGlobal {
            Button("Make Global") {
                activeAlert = .confirmMakeGlobal(skill)
            }
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
            if !skill.isReadOnly {
                Divider()
            }
        } else if !skill.isReadOnly {
            Divider()
        }
        if !skill.isReadOnly {
            Button("Delete", role: .destructive) {
                trashSkills([skill], restoreSelectionOnUndo: true)
            }
        }
    }

    private func makeSkillGlobal(_ skill: Skill) {
        do {
            try skill.makeGlobal()
            try? modelContext.save()
        } catch {
            activeAlert = .makeGlobalError(error.localizedDescription)
        }
    }

    private func createNote() {
        do {
            let fileURL = try NotesService.createBlankNote()
            let initialContent = NotesService.initialContent
            let note = NotesService.makeIndexedNote(
                fileURL: fileURL,
                content: initialContent,
                fileModifiedDate: .now,
                fileSize: initialContent.utf8.count
            )
            modelContext.insert(note)
            try modelContext.save()

            appState.searchText = ""
            appState.toolKindFilter = nil
            appState.sidebarFilter = .allNotes
            appState.selectOnly(note)
        } catch {
            activeAlert = .createNoteError(error.localizedDescription)
        }
    }

    private func trashSelectedSkills() {
        trashSkills(selectedSkills, restoreSelectionOnUndo: selectedSkills.count == 1)
    }

    private func trashSkills(_ skills: [Skill], restoreSelectionOnUndo: Bool) {
        let deletableSkills = Array(
            Dictionary(
                uniqueKeysWithValues: skills
                    .filter { !$0.isRemote && !$0.isReadOnly }
                    .map { ($0.resolvedPath, $0) }
            ).values
        )
        guard !deletableSkills.isEmpty else { return }

        let deletedPaths = Set(deletableSkills.map(\.resolvedPath))
        let remainingSkills = filteredSkills.filter { !deletedPaths.contains($0.resolvedPath) }
        var trashOperation: SkillTrashOperation?

        do {
            let operation = try SkillTrashOperation.trash(deletableSkills)
            trashOperation = operation

            for skill in deletableSkills {
                modelContext.delete(skill)
            }
            do {
                try modelContext.save()
            } catch {
                _ = try? operation.restore(in: modelContext)
                try? modelContext.save()
                throw error
            }

            appState.selectedSkillPaths.subtract(deletedPaths)
            appState.repairSelection(in: remainingSkills)

            undoManager?.registerUndo(withTarget: modelContext) { context in
                do {
                    let restoredSkills = try operation.restore(in: context)
                    try context.save()

                    if restoreSelectionOnUndo, restoredSkills.count == 1 {
                        appState.selectOnly(restoredSkills[0])
                    }
                } catch {
                    activeAlert = .deleteError(error.localizedDescription)
                }
            }
            undoManager?.setActionName("Move to Trash")
        } catch {
            if let trashOperation {
                _ = try? trashOperation.restore(in: modelContext)
                try? modelContext.save()
            }
            activeAlert = .deleteError(error.localizedDescription)
        }
    }

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(filteredSkills) { skill in
                SkillRow(skill: skill, showTypeBadge: showsTypeBadge)
                    .tag(skill.resolvedPath)
                    .draggable(skill.resolvedPath)
                    .contextMenu { contextMenu(for: skill) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !skill.isRemote && !skill.isReadOnly {
                            Button("Delete", role: .destructive) {
                                trashSkills([skill], restoreSelectionOnUndo: true)
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .onDeleteCommand(perform: trashSelectedSkills)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if case .tool = appState.sidebarFilter, availableKinds.count > 1 {
                        Menu {
                            Button {
                                appState.toolKindFilter = nil
                            } label: {
                                if appState.toolKindFilter == nil {
                                    Label("All", systemImage: "checkmark")
                                } else {
                                    Text("All")
                                }
                            }
                            Divider()
                            ForEach(availableKinds, id: \.self) { kind in
                                Button {
                                    appState.toolKindFilter = kind
                                } label: {
                                    if appState.toolKindFilter == kind {
                                        Label(kind.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(kind.displayName)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: appState.toolKindFilter != nil ? "ellipsis.circle.fill" : "ellipsis.circle")
                        }
                        .help("Filter by Type")
                        .accessibilityLabel("Filter by Type")
                    }
                    if isNotesLibraryView {
                        Button {
                            createNote()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("New Note")
                        .accessibilityLabel("New Note")
                    } else {
                        Menu {
                            Button {
                                createNote()
                            } label: {
                                Label("New Note", systemImage: "note.text")
                            }
                            Divider()
                            Button {
                                appState.newItemKind = .skill
                                appState.showingNewSkillSheet = true
                            } label: {
                                Label("New Skill", systemImage: "doc.text")
                            }
                            Button {
                                appState.newItemKind = .agent
                                appState.showingNewSkillSheet = true
                            } label: {
                                Label("New Agent", systemImage: "person.crop.rectangle")
                            }
                            Button {
                                appState.newItemKind = .rule
                                appState.showingNewSkillSheet = true
                            } label: {
                                Label("New Rule", systemImage: "list.bullet.rectangle")
                            }
                            Divider()
                            Button {
                                appState.showingRegistrySheet = true
                            } label: {
                                Label("Browse Registry", systemImage: "globe")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .menuIndicator(.hidden)
                        .help("New Item")
                        .accessibilityLabel("New Item")
                    }
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .createNoteError(let message):
                return Alert(
                    title: Text("Create Note Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .confirmMakeGlobal(let skill):
                return Alert(
                    title: Text("Make \"\(skill.name)\" Global?"),
                    message: Text("This will move the skill to ~/.agents/skills/ and symlink it to all installed agents."),
                    primaryButton: .default(Text("Make Global")) {
                        makeSkillGlobal(skill)
                    },
                    secondaryButton: .cancel()
                )
            case .deleteError(let message):
                return Alert(
                    title: Text("Move to Trash Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .makeGlobalError(let message):
                return Alert(
                    title: Text("Make Global Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .overlay {
            if filteredSkills.isEmpty { emptyStateView }
        }
        .onAppear {
            appState.repairSelection(in: filteredSkills)
        }
        .onChange(of: appState.sidebarFilter) {
            appState.repairSelection(in: filteredSkills)
        }
        .onChange(of: appState.searchText) {
            appState.repairSelection(in: filteredSkills)
        }
        .onChange(of: filteredSkillPaths) {
            appState.repairSelection(in: filteredSkills)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNoteRequested)) { _ in
            guard isNotesLibraryView else { return }
            createNote()
        }
    }
}

struct SkillRow: View {
    let skill: Skill
    var showTypeBadge: Bool = false

    var body: some View {
        Group {
            if skill.itemKind == .note {
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .lineLimit(1)

                        if skill.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(NSColor.systemYellow))
                        }
                    }

                    Spacer(minLength: 8)

                    Text(skill.fileModifiedDate.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 8) {
                    if showTypeBadge {
                        let kindIcon: String = switch skill.itemKind {
                        case .note: "note.text"
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
                            .foregroundStyle(Color(NSColor.systemYellow))
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

                    HStack(spacing: 4) {
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
        .accessibilityElement(children: .combine)
    }
}
