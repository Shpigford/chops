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
            SkillListView()
        } detail: {
            if let skill = appState.selectedSkill {
                SkillDetailView(skill: skill)
            } else {
                switch appState.sidebarFilter {
                case .allAgents:
                    ContentUnavailableView(
                        "content.selectAgent".localized,
                        systemImage: "person.crop.rectangle",
                        description: Text("content.selectAgentDescription".localized)
                    )
                default:
                    ContentUnavailableView(
                        "content.selectSkill".localized,
                        systemImage: "doc.text",
                        description: Text("content.selectSkillDescription".localized)
                    )
                }
            }
        }
        .searchable(text: $appState.searchText, prompt: appState.sidebarFilter == .allAgents ? "content.searchAgents".localized : "content.searchSkills".localized)
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
                        Label("content.newSkill".localized, systemImage: "doc.text")
                    }
                    Button {
                        appState.newItemKind = .agent
                        appState.showingNewSkillSheet = true
                    } label: {
                        Label("content.newAgent".localized, systemImage: "person.crop.rectangle")
                    }
                    Divider()
                    Button {
                        appState.showingRegistrySheet = true
                    } label: {
                        Label("content.browseRegistry".localized, systemImage: "globe")
                    }
                } label: {
                    Label("content.add".localized, systemImage: "plus")
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
