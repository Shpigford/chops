import ACPRegistry
import SwiftUI

struct ACPSettingsView: View {
    @State private var configuration = ACPConfiguration.shared

    var body: some View {
        Form {
            Section {
                Text("Enable AI assistants to help compose and improve skills, agents, and rules.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            agentListSection

            Section {
                Button("Refresh Registry") {
                    Task { await configuration.refreshRegistry() }
                }
                .disabled(configuration.isLoadingRegistry)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await configuration.loadRegistryIfNeeded() }
    }

    // MARK: - Agent List

    @ViewBuilder
    private var agentListSection: some View {
        Section {
            if configuration.isLoadingRegistry {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading registry…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = configuration.registryError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if configuration.registryAgents.isEmpty {
                Text("No agents found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(configuration.registryAgents) { agent in
                    AgentRow(agent: agent, configuration: configuration)
                }
            }
        } header: {
            Text("Agents")
        }
    }
}

// MARK: - Agent Row

private struct AgentRow: View {
    let agent: RegistryAgent
    @Bindable var configuration: ACPConfiguration

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .fontWeight(.medium)
                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("v\(agent.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { configuration.isEnabled(agent.id) },
                set: { configuration.setEnabled(agent.id, $0) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    ACPSettingsView()
        .frame(width: 500, height: 500)
}
