import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var skills: [Skill]
    @State private var scanner: SkillScanner?
    @State private var mcpScanner: MCPScanner?
    @State private var fileWatcher: FileWatcher?
    @State private var mcpFileWatcher: FileWatcher?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            if appState.sidebarFilter == .allMCPServers {
                MCPListView()
            } else {
                SkillListView()
            }
        } detail: {
            if appState.sidebarFilter == .allMCPServers {
                if let server = appState.selectedMCPServer {
                    MCPDetailView(server: server)
                } else {
                    ContentUnavailableView(
                        "Select a Server",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Choose an MCP server to view its configuration.")
                    )
                }
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
        .onChange(of: appState.sidebarFilter) {
            appState.toolKindFilter = nil
        }
        .frame(minWidth: 900, minHeight: 500)
        .onReceive(NotificationCenter.default.publisher(for: .customScanPathsChanged)) { _ in
            scanner?.scanAll()
            mcpScanner?.scanAll()
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
        allPaths = Array(Set(allPaths)).sorted()

        let watcher = FileWatcher { _ in
            scanner.scanAll()
            scanner.removeDeletedSkills()
        }
        watcher.watchDirectories(allPaths)
        self.fileWatcher = watcher
        AppLogger.ui.notice("File watchers active on \(allPaths.count) directories")

        // MCP server scanning
        let mcpScanner = MCPScanner(modelContext: modelContext)
        self.mcpScanner = mcpScanner
        mcpScanner.scanAll()

        var mcpPaths: [String] = []
        for tool in ToolSource.allCases {
            for path in tool.mcpConfigPaths {
                let expanded = (path as NSString).expandingTildeInPath
                if fm.fileExists(atPath: expanded) {
                    mcpPaths.append(expanded)
                }
            }
        }
        let customPaths = UserDefaults.standard.stringArray(forKey: "customScanPaths") ?? []
        for basePath in customPaths where fm.fileExists(atPath: basePath) {
            mcpPaths.append(basePath)
        }
        if !mcpPaths.isEmpty {
            let mcpWatcher = FileWatcher { _ in
                mcpScanner.scanAll()
            }
            mcpWatcher.watchDirectories(mcpPaths)
            self.mcpFileWatcher = mcpWatcher
            AppLogger.ui.notice("MCP file watchers active on \(mcpPaths.count) paths")
        }

        // Sync remote servers in the background
        Task {
            await scanner.syncAllRemoteServers()
        }
    }
}
