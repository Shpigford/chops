import SwiftUI
import SwiftData

struct MCPListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \MCPServer.name) private var allServers: [MCPServer]

    private var filteredServers: [MCPServer] {
        if appState.searchText.isEmpty {
            return allServers
        }
        return allServers.filter {
            $0.name.localizedCaseInsensitiveContains(appState.searchText) ||
            $0.toolSource.displayName.localizedCaseInsensitiveContains(appState.searchText) ||
            ($0.command ?? "").localizedCaseInsensitiveContains(appState.searchText) ||
            ($0.url ?? "").localizedCaseInsensitiveContains(appState.searchText)
        }
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedMCPServer) {
            ForEach(filteredServers) { server in
                MCPServerRow(server: server)
                    .tag(server)
            }
        }
        .navigationTitle("MCP Servers")
        .overlay {
            if filteredServers.isEmpty {
                ContentUnavailableView(
                    "No MCP Servers",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("No MCP servers found in your tool configurations.")
                )
            }
        }
        .onChange(of: appState.sidebarFilter) {
            if appState.sidebarFilter == .allMCPServers {
                if let selected = appState.selectedMCPServer, filteredServers.contains(selected) {
                } else {
                    appState.selectedMCPServer = filteredServers.first
                }
            }
        }
        .onAppear {
            if appState.selectedMCPServer == nil {
                appState.selectedMCPServer = filteredServers.first
            }
        }
    }
}

struct MCPServerRow: View {
    let server: MCPServer

    var body: some View {
        HStack(spacing: 8) {
            Text(server.name)
                .lineLimit(1)

            Spacer()

            Text(server.displayTransport)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))

            ToolIcon(tool: server.toolSource, size: 14)
                .opacity(0.6)
                .help(server.toolSource.displayName)
        }
        .padding(.vertical, 4)
    }
}
