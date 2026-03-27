import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \SkillCollection.sortOrder) private var collections: [SkillCollection]
    @Query(sort: \RemoteServer.label) private var servers: [RemoteServer]
    @State private var syncingServerIDs: Set<String> = []
    @State private var serverErrors: [String: String] = [:]
    @State private var showingErrorForServer: String?

    private var activeSources: [ToolSource] {
        ToolSource.allCases.filter { tool in
            allSkills.contains { $0.toolSources.contains(tool) }
        }
    }

    private func toolCount(_ tool: ToolSource) -> Int {
        allSkills.filter { $0.toolSources.contains(tool) }.count
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.sidebarFilter) {
            Section("sidebar.library".localized) {
                Label("sidebar.allSkills".localized, systemImage: "doc.text")
                    .badge(allSkills.filter { $0.itemKind == .skill }.count)
                    .tag(SidebarFilter.allSkills)

                Label("sidebar.allAgents".localized, systemImage: "person.crop.rectangle")
                    .badge(allSkills.filter { $0.itemKind == .agent }.count)
                    .tag(SidebarFilter.allAgents)

                Label("sidebar.favorites".localized, systemImage: "star")
                    .badge(allSkills.filter(\.isFavorite).count)
                    .tag(SidebarFilter.favorites)
            }

            Section("sidebar.tools".localized) {
                ForEach(activeSources) { tool in
                    Label {
                        Text(tool.displayName)
                    } icon: {
                        ToolIcon(tool: tool)
                    }
                    .badge(toolCount(tool))
                    .tag(SidebarFilter.tool(tool))
                }
            }

            if !servers.isEmpty {
                Section("sidebar.servers".localized) {
                    ForEach(servers) { server in
                        HStack {
                            Label {
                                Text(server.label)
                            } icon: {
                                Image(systemName: "server.rack")
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let error = serverErrors[server.id] {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .popover(isPresented: Binding(
                                        get: { showingErrorForServer == server.id },
                                        set: { if !$0 { showingErrorForServer = nil } }
                                    )) {
                                        Text(error)
                                            .font(.caption)
                                            .padding()
                                            .frame(maxWidth: 250)
                                    }
                                    .onTapGesture {
                                        showingErrorForServer = server.id
                                    }
                            }

                            Button {
                                syncServer(server)
                            } label: {
                                if syncingServerIDs.contains(server.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("sidebar.syncFromServer".localized)
                            .disabled(syncingServerIDs.contains(server.id))
                        }
                        .badge(server.skills.count)
                        .tag(SidebarFilter.server(server.id))
                    }
                }
            }

            Section("sidebar.collections".localized) {
                CollectionListView()
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("sidebar.appTitle".localized)
    }

    private func syncServer(_ server: RemoteServer) {
        syncingServerIDs.insert(server.id)
        serverErrors.removeValue(forKey: server.id)
        Task {
            let scanner = SkillScanner(modelContext: modelContext)
            await scanner.scanRemoteServer(server)
            await MainActor.run {
                syncingServerIDs.remove(server.id)
                if let error = server.lastSyncError {
                    serverErrors[server.id] = error
                }
            }
        }
    }
}
