import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var skills: [Skill]
    @State private var scanner: SkillScanner?
    @State private var fileWatcher: FileWatcher?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var searchPrompt: LocalizedStringKey {
        switch appState.sidebarFilter {
        case .allNotes:
            "Search notes..."
        case .allAgents:
            "Search agents..."
        case .allRules:
            "Search rules..."
        case .allSkills:
            "Search skills..."
        case .favorites:
            "Search favorites..."
        case .tool, .collection, .server:
            "Search items..."
        }
    }

    private var emptySelectionTitle: LocalizedStringKey {
        switch appState.sidebarFilter {
        case .allNotes:
            "Select a Note"
        case .allAgents:
            "Select an Agent"
        case .allRules:
            "Select a Rule"
        case .allSkills:
            "Select a Skill"
        case .favorites, .tool, .collection, .server:
            "Select an Item"
        }
    }

    private var emptySelectionIcon: String {
        switch appState.sidebarFilter {
        case .allNotes:
            ItemKind.note.icon
        case .allAgents:
            ItemKind.agent.icon
        case .allRules:
            ItemKind.rule.icon
        case .allSkills, .favorites, .tool, .collection, .server:
            ItemKind.skill.icon
        }
    }

    private var emptySelectionDescription: LocalizedStringKey {
        switch appState.sidebarFilter {
        case .allNotes:
            "Choose a note from the sidebar to view and edit it."
        case .allAgents:
            "Choose an agent from the sidebar to view and edit it."
        case .allRules:
            "Choose a rule from the sidebar to view and edit it."
        case .allSkills:
            "Choose a skill from the sidebar to view and edit it."
        case .favorites:
            "Choose an item from favorites to view and edit it."
        case .tool, .collection, .server:
            "Choose an item from the list to view and edit it."
        }
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            SkillListView()
        } detail: {
            if let skill = appState.selectedSkill {
                SkillDetailView(skill: skill)
            } else {
                ContentUnavailableView(
                    emptySelectionTitle,
                    systemImage: emptySelectionIcon,
                    description: Text(emptySelectionDescription)
                )
            }
        }
        .searchable(text: $appState.searchText, prompt: searchPrompt)
        .onAppear {
            AppLogger.lifecycle.notice("ContentView onAppear sidebarFilter=\(String(describing: appState.sidebarFilter), privacy: .public)")
            AppRuntimeDiagnostics.logSnapshot(reason: "ContentView.onAppear before scan")
            startScanning(syncRemote: true)
            AppRuntimeDiagnostics.logSnapshot(reason: "ContentView.onAppear after scan setup")
        }
        .onDisappear {
            AppLogger.lifecycle.notice("ContentView onDisappear")
            AppRuntimeDiagnostics.logSnapshot(reason: "ContentView.onDisappear")
        }
        .sheet(isPresented: $appState.showingNewSkillSheet) {
            NewSkillSheet()
        }
        .sheet(isPresented: $appState.showingRegistrySheet) {
            RegistrySheet()
        }
        .onChange(of: appState.sidebarFilter) {
            appState.toolKindFilter = nil
            AppLogger.ui.notice("Sidebar filter changed to \(String(describing: appState.sidebarFilter), privacy: .public)")
        }
        .frame(minWidth: 900, minHeight: 500)
        .onReceive(NotificationCenter.default.publisher(for: .customScanPathsChanged)) { _ in
            AppLogger.lifecycle.notice("Received customScanPathsChanged notification")
            AppRuntimeDiagnostics.logSnapshot(reason: "customScanPathsChanged before rescan")
            startScanning(syncRemote: false)
        }
    }

    private func startScanning(syncRemote: Bool) {
        AppLogger.ui.notice("startScanning syncRemote=\(syncRemote)")
        do {
            try NotesService.ensureNotesDirectoryExists()
        } catch {
            AppLogger.fileIO.error("Failed to prepare notes directory: \(error.localizedDescription)")
        }
        let scanner = SkillScanner(modelContext: modelContext)
        self.scanner = scanner
        scanner.removeDeletedSkills()
        scanner.scanAll()

        var allPaths: [String] = []
        for tool in ToolSource.allCases {
            allPaths.append(contentsOf: tool.globalPaths)
            allPaths.append(contentsOf: tool.globalAgentPaths)
            allPaths.append(contentsOf: tool.globalRulePaths)
        }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let claudePlugins = "\(home)/.claude/plugins"
        let claudePluginCache = "\(claudePlugins)/cache"
        let claudePluginManifest = "\(claudePlugins)/installed_plugins.json"
        for path in [claudePlugins, claudePluginCache, claudePluginManifest] where fm.fileExists(atPath: path) {
            allPaths.append(path)
        }
        let claudeDesktopSessions = "\(home)/Library/Application Support/Claude/local-agent-mode-sessions"
        if fm.fileExists(atPath: claudeDesktopSessions) {
            allPaths.append(claudeDesktopSessions)
        }
        allPaths.append(NotesService.notesDirectoryPath)
        allPaths = Array(Set(allPaths)).sorted()

        let watcher = FileWatcher { _ in
            scanner.scanAll()
            scanner.removeDeletedSkills()
        }
        watcher.watchDirectories(allPaths)
        self.fileWatcher = watcher
        AppLogger.ui.notice("File watchers active on \(allPaths.count) directories")
        let watchedPaths = allPaths.joined(separator: " | ")
        AppLogger.ui.notice("Watching paths: \(watchedPaths, privacy: .public)")
        AppRuntimeDiagnostics.logSnapshot(reason: "startScanning configured watchers")

        if syncRemote {
            Task {
                await scanner.syncAllRemoteServers()
            }
        }
    }
}
