import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var skills: [Skill]
    @State private var scanner: SkillScanner?
    @State private var fileWatcher: FileWatcher?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            ZStack {
                if case .tool(let tool) = appState.sidebarFilter, appState.selectedKindFilter == nil {
                    ToolKindPickerView(tool: tool)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading),
                            removal: .move(edge: .leading)
                        ))
                } else if appState.sidebarFilter == .composer {
                    ComposerPickerView()
                        .transition(.opacity)
                } else {
                    SkillListView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: appState.selectedKindFilter)
            .onChange(of: appState.sidebarFilter) { _, newFilter in
                if case .tool = newFilter { } else {
                    appState.selectedKindFilter = nil
                }
                if case .composer = newFilter { } else {
                    appState.selectedTemplateType = nil
                }
            }
        } detail: {
            if let templateType = appState.selectedTemplateType {
                TemplateDetailView(templateType: templateType)
            } else if let skill = appState.selectedSkill {
                SkillDetailView(skill: skill)
            } else {
                ContentUnavailableView(
                    "Select a Skill",
                    systemImage: "doc.text",
                    description: Text("Choose a skill from the sidebar to view and edit it.")
                )
            }
        }
        .searchable(text: $appState.searchText, prompt: "Search skills...")
        .onAppear {
            startScanning()
        }
        .sheet(isPresented: $appState.showingNewSkillSheet) {
            NewSkillSheet()
        }
        .sheet(isPresented: $appState.showingRegistrySheet) {
            RegistrySheet()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        appState.newItemKind = .skill
                        appState.showingNewSkillSheet = true
                    } label: {
                        Label("New Skill", systemImage: "doc.text")
                    }
                    Divider()
                    Button {
                        appState.showingRegistrySheet = true
                    } label: {
                        Label("Browse Registry", systemImage: "globe")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuIndicator(.hidden)
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .onReceive(NotificationCenter.default.publisher(for: .customScanPathsChanged)) { _ in
            scanner?.scanAll()
        }
    }

    private func startScanning() {
        AppLogger.ui.notice("App started, beginning initial scan")
        let scanner = SkillScanner(modelContext: modelContext)
        self.scanner = scanner
        scanner.removeDeletedSkills()
        scanner.scanAll()

        var allPaths: [String] = []
        for tool in ToolSource.allCases {
            allPaths.append(contentsOf: tool.globalPaths)
            allPaths.append(contentsOf: tool.globalAgentPaths)
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
        allPaths = Array(Set(allPaths)).sorted()

        let watcher = FileWatcher { _ in
            scanner.scanAll()
            scanner.removeDeletedSkills()
        }
        watcher.watchDirectories(allPaths)
        self.fileWatcher = watcher
        AppLogger.ui.notice("File watchers active on \(allPaths.count) directories")

        // Sync remote servers in the background
        Task {
            await scanner.syncAllRemoteServers()
        }
    }
}
