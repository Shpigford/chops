import SwiftUI
import SwiftData

struct SkillListView: View {
    private enum ActiveAlert: Identifiable {
        case confirmDelete(Skill)
        case deleteError(String)
        case symlinkError(String)

        var id: String {
            switch self {
            case .confirmDelete(let skill): "confirm-delete-\(skill.filePath)"
            case .deleteError(let message): "delete-error-\(message)"
            case .symlinkError(let message): "symlink-error-\(message)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \SkillCollection.name) private var allCollections: [SkillCollection]
    @State private var activeAlert: ActiveAlert?
    @State private var categorySelection: SkillCategory?
    @State private var multiSelectMode = false
    @State private var multiSelection: Set<String> = []
    @State private var showingSymlinkPicker = false
    @State private var showingUnlinkPicker = false
    @State private var symlinkTargets: Set<ToolSource> = []
    @State private var unlinkTargets: Set<ToolSource> = []

    private var filteredSkills: [Skill] {
        var result = allSkills

        switch appState.sidebarFilter {
        case .all:
            break
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .category(let category):
            result = result.filter { $0.category == category }
        case .tool(let tool):
            result = result.filter { $0.toolSources.contains(tool) }
        case .toolCategory(let tool, let category):
            result = result.filter { $0.toolSources.contains(tool) && $0.category == category }
        case .collection(let collName):
            result = result.filter { skill in
                skill.collections.contains { $0.name == collName }
            }
        case .server(let serverID):
            result = result.filter { $0.remoteServer?.id == serverID }
        case .wizardTemplate:
            result = []  // Templates shown in separate view
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
        case .all: "All"
        case .favorites: "Favorites"
        case .category(let category): category.displayName
        case .tool(let tool): tool.displayName
        case .toolCategory(_, let category): category.displayName
        case .collection(let name): name
        case .server(let id):
            allSkills.first(where: { $0.remoteServer?.id == id })?.remoteServer?.label ?? "Remote Skills"
        case .wizardTemplate(let templateType): templateType.displayName
        }
    }

    private var selectedSkills: [Skill] {
        filteredSkills.filter { multiSelection.contains($0.resolvedPath) }
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

    private func applySymlinks() {
        let targets = Array(symlinkTargets)
        do {
            try SymlinkService.symlink(selectedSkills, to: targets)
            try? modelContext.save()
        } catch {
            activeAlert = .symlinkError(error.localizedDescription)
        }
        resetSelectionState()
    }

    private func applyUnlinks() {
        let targets = Array(unlinkTargets)
        do {
            try SymlinkService.unlink(selectedSkills, from: targets)
            try? modelContext.save()
        } catch {
            activeAlert = .symlinkError(error.localizedDescription)
        }
        resetSelectionState()
    }

    private func unlinkSingle(skill: Skill, from tool: ToolSource) {
        do {
            try SymlinkService.unlink([skill], from: [tool])
            try? modelContext.save()
        } catch {
            activeAlert = .symlinkError(error.localizedDescription)
        }
    }

    private func resetSelectionState() {
        showingSymlinkPicker = false
        showingUnlinkPicker = false
        multiSelectMode = false
        multiSelection.removeAll()
        symlinkTargets.removeAll()
        unlinkTargets.removeAll()
    }

    /// Tools that have links from any of the selected skills
    private var linkedToolsInSelection: Set<ToolSource> {
        var tools = Set<ToolSource>()
        for skill in selectedSkills {
            for tool in skill.linkedTools {
                tools.insert(tool)
            }
        }
        return tools
    }

    var body: some View {
        if case .tool(let tool) = appState.sidebarFilter {
            categoryBrowser(tool: tool)
        } else {
            skillListBody()
        }
    }

    @ViewBuilder
    private func categoryBrowser(tool: ToolSource) -> some View {
        let toolSkills = allSkills.filter { $0.toolSources.contains(tool) }
        let counts = toolSkills.reduce(into: [SkillCategory: Int]()) { acc, skill in
            acc[skill.category, default: 0] += 1
        }
        let available = SkillCategory.allCases.filter { counts[$0, default: 0] > 0 }

        List(selection: $categorySelection) {
            ForEach(available, id: \.self) { category in
                let count = counts[category, default: 0]
                HStack(spacing: 10) {
                    Label(category.displayName, systemImage: category.icon)
                        .font(.callout)
                    Spacer()
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .font(.callout)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .tag(category)
            }
        }
        .navigationTitle(tool.displayName)
        .onChange(of: categorySelection) { _, cat in
            guard let cat else { return }
            appState.sidebarFilter = .toolCategory(tool, cat)
            appState.selectedSkill = nil
            categorySelection = nil
        }
        .overlay {
            if available.isEmpty {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: "doc.text",
                    description: Text("No skills found for \(tool.displayName).")
                )
            }
        }
    }

    private func skillListBody() -> some View {
        VStack(spacing: 0) {
            breadcrumbBar()
            
            if multiSelectMode {
                linkControlsBar
            }

            List(selection: multiSelectMode ? Binding<Skill?>.constant(nil) : Binding(
                get: { appState.selectedSkill },
                set: { appState.selectedSkill = $0 }
            )) {
                ForEach(filteredSkills) { skill in
                    SkillRow(
                        skill: skill,
                        showCheckbox: multiSelectMode,
                        isChecked: multiSelection.contains(skill.resolvedPath),
                        onToggle: { checked in
                            if checked { multiSelection.insert(skill.resolvedPath) }
                            else { multiSelection.remove(skill.resolvedPath) }
                        },
                        onUnlink: { skill, tool in
                            unlinkSingle(skill: skill, from: tool)
                        }
                    )
                    .tag(skill)
                    .draggable(skill.resolvedPath)
                    .contextMenu {
                        Button(skill.isFavorite ? "Unfavorite" : "Favorite") {
                            skill.isFavorite.toggle()
                            try? modelContext.save()
                        }
                        Button(skill.isBase ? "Unmark as Base" : "Mark as Base") {
                            skill.isBase.toggle()
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
                }
            }
            .navigationTitle(title)
        }
        .toolbar {
            ToolbarItem {
                Button(multiSelectMode ? "Done" : "Link") {
                    multiSelectMode.toggle()
                    if !multiSelectMode {
                        multiSelection.removeAll()
                        symlinkTargets.removeAll()
                    }
                }
                .font(.callout)
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmDelete(let skill):
                return Alert(
                    title: Text("Delete Skill?"),
                    message: Text("This will permanently delete \"\(skill.name)\" from disk."),
                    primaryButton: .destructive(Text("Delete")) { deleteSkill(skill) },
                    secondaryButton: .cancel()
                )
            case .deleteError(let message):
                return Alert(
                    title: Text("Delete Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .symlinkError(let message):
                return Alert(
                    title: Text("Symlink Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
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

    @ViewBuilder
    private func breadcrumbBar() -> some View {
        if case .toolCategory(let tool, let category) = appState.sidebarFilter {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Button {
                        appState.sidebarFilter = .tool(tool)
                        appState.selectedSkill = nil
                        multiSelectMode = false
                        multiSelection.removeAll()
                        symlinkTargets.removeAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tool.iconName)
                                .font(.caption2)
                            Text(tool.displayName)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(category.displayName)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor))
                Divider()
            }
        }
    }

    private var linkControlsBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if multiSelection.count == filteredSkills.count {
                        multiSelection.removeAll()
                    } else {
                        multiSelection = Set(filteredSkills.map(\.resolvedPath))
                    }
                } label: {
                    Text(multiSelection.count == filteredSkills.count ? "Deselect All" : "Select All")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if !multiSelection.isEmpty {
                    Text("•")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)

                    Text("\(multiSelection.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !multiSelection.isEmpty {
                    Button("Symlink to...") {
                        showingSymlinkPicker.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: $showingSymlinkPicker, arrowEdge: .top) {
                        symlinkPickerView
                    }

                    if !linkedToolsInSelection.isEmpty {
                        Button("Unlink from...") {
                            showingUnlinkPicker.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .popover(isPresented: $showingUnlinkPicker, arrowEdge: .top) {
                            unlinkPickerView
                        }
                    }
                }

                Button {
                    resetSelectionState()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Cancel selection")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
        }
    }

    private var symlinkPickerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Symlink to")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(ToolSource.allCases.filter(\.listable)) { tool in
                    let alreadyAll = selectedSkills.allSatisfy { $0.toolSources.contains(tool) }
                    Toggle(isOn: Binding(
                        get: { symlinkTargets.contains(tool) },
                        set: { on in
                            if on { symlinkTargets.insert(tool) }
                            else { symlinkTargets.remove(tool) }
                        }
                    )) {
                        HStack(spacing: 6) {
                            ToolIcon(tool: tool, size: 14)
                            Text(tool.displayName)
                            if alreadyAll {
                                Text("(already installed)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(alreadyAll)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    showingSymlinkPicker = false
                    symlinkTargets.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Apply") {
                    applySymlinks()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(symlinkTargets.isEmpty)
            }
        }
        .padding()
        .frame(width: 240)
    }

    private var unlinkPickerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unlink from")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(linkedToolsInSelection).sorted(by: { $0.displayName < $1.displayName }), id: \.self) { tool in
                    Toggle(isOn: Binding(
                        get: { unlinkTargets.contains(tool) },
                        set: { on in
                            if on { unlinkTargets.insert(tool) }
                            else { unlinkTargets.remove(tool) }
                        }
                    )) {
                        HStack(spacing: 6) {
                            ToolIcon(tool: tool, size: 14)
                            Text(tool.displayName)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    showingUnlinkPicker = false
                    unlinkTargets.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Unlink") {
                    applyUnlinks()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .disabled(unlinkTargets.isEmpty)
            }
        }
        .padding()
        .frame(width: 240)
    }
}

struct SkillRow: View {
    let skill: Skill
    var showCheckbox: Bool = false
    var isChecked: Bool = false
    var onToggle: ((Bool) -> Void)? = nil
    var onUnlink: ((Skill, ToolSource) -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if showCheckbox {
                Toggle("", isOn: Binding(
                    get: { isChecked },
                    set: { onToggle?($0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            if skill.isBase {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.blue)
                    .help("Base skill")
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
                    let isLinked = skill.linkedTools.contains(tool)
                    HStack(spacing: 2) {
                        ToolIcon(tool: tool, size: 14)
                            .opacity(isLinked ? 0.5 : 0.7)

                        if isLinked && isHovering {
                            Button {
                                onUnlink?(skill, tool)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Unlink from \(tool.displayName)")
                        }
                    }
                    .help(isLinked ? "Linked in \(tool.displayName)" : "Installed in \(tool.displayName)")
                }
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
