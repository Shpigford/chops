import SwiftUI
import SwiftData

/// Shown when a tool is selected in the sidebar before a kind (Skills / Agents / Rules) is chosen.
struct ToolKindPickerView: View {
    let tool: ToolSource

    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var allSkills: [Skill]

    private var rows: [(kind: ItemKind, count: Int)] {
        ItemKind.allCases.compactMap { kind in
            let count = allSkills.filter { $0.toolSources.contains(tool) && $0.itemKind == kind }.count
            return count > 0 ? (kind, count) : nil
        }
    }

    var body: some View {
        List {
            ForEach(rows, id: \.kind) { row in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.selectedKindFilter = row.kind
                    }
                } label: {
                    HStack {
                        Label(row.kind.displayName, systemImage: row.kind.icon)
                        Spacer()
                        Text("\(row.count)")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(tool.displayName)
    }
}
