import SwiftUI
import SwiftData

struct ToolFilterView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var allSkills: [Skill]

    private func count(for tool: ToolSource) -> Int {
        allSkills.filter { $0.toolSources.contains(tool) }.count
    }

    private var activeSources: [ToolSource] {
        ToolSource.allCases.filter { tool in
            allSkills.contains { $0.toolSources.contains(tool) }
        }
    }

    var body: some View {
        ForEach(activeSources) { tool in
            Button {
                if appState.sidebarFilter == .tool(tool) {
                    appState.sidebarFilter = .allSkills
                } else {
                    appState.sidebarFilter = .tool(tool)
                }
            } label: {
                HStack {
                    Text(tool.displayName)
                    Spacer()
                    Text("\(count(for: tool))")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .fontWeight(appState.sidebarFilter == .tool(tool) ? .semibold : .regular)
        }
    }
}
