import SwiftUI

struct AgentSettingsView: View {
    @State private var configuration = AgentConfiguration.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enable AI assistants to help compose and improve skills, agents, and rules.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                agentListSection
            }
            .padding()
        }
        .frame(maxHeight: 550)
    }

    @ViewBuilder
    private var agentListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(configuration.supported) { id in
                    AgentRow(agentId: id, configuration: configuration)
                    if id != configuration.supported.last {
                        Divider()
                    }
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Agent Row

private struct AgentRow: View {
    let agentId: AgentID
    @Bindable var configuration: AgentConfiguration
    @State private var localBinaryPath: String?
    @State private var localVersion: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(agentId.displayName)
                    .fontWeight(.medium)
                if localBinaryPath != nil {
                    let v = localVersion.map { " v\($0)" } ?? ""
                    Text("Uses your installed \(agentId.displayName)\(v)")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                    if let path = localBinaryPath {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("\(agentId.displayName) isn't installed.")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .lineLimit(2)
                    Link("Install \(agentId.displayName) →", destination: agentId.installURL)
                        .font(.caption2)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { configuration.isEnabled(agentId) },
                set: { configuration.setEnabled(agentId, $0) }
            ))
            .labelsHidden()
            .disabled(localBinaryPath == nil)
        }
        .padding(.vertical, 4)
        .task(id: agentId.id) {
            await refreshLocalBinaryStatus()
        }
    }

    private func refreshLocalBinaryStatus() async {
        let source = agentId.toolSource
        if let url = source.cliBinaryURL {
            localBinaryPath = url.path
            if let v = await source.cliVersion() {
                localVersion = "\(v.major).\(v.minor).\(v.patch)"
            }
        } else {
            localBinaryPath = nil
            localVersion = nil
        }
    }
}

#Preview {
    AgentSettingsView()
        .frame(width: 480)
}
