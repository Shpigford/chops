import ACPRegistry
import SwiftUI

struct ACPSettingsView: View {
    @State private var configuration = ACPConfiguration.shared
    @State private var templateManager = TemplateManager.shared
    @State private var templateContents: [WizardTemplateType: String] = [:]
    @State private var templateChanges: Set<WizardTemplateType> = []
    @State private var showingResetConfirm: WizardTemplateType?
    @State private var expandedTemplates: Set<WizardTemplateType> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enable AI assistants to help compose and improve skills, agents, and rules.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                agentListSection

                HStack {
                    Button("Refresh Registry") {
                        Task { await configuration.refreshRegistry() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(configuration.isLoadingRegistry)
                }

                Divider()

                templateSection
            }
            .padding(20)
        }
        .frame(maxHeight: 550)
        .task { await configuration.loadRegistryIfNeeded() }
        .onAppear { loadAllTemplates() }
    }

    // MARK: - Agent List

    @ViewBuilder
    private var agentListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents")
                .font(.headline)

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
                        .symbolRenderingMode(.multicolor)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if configuration.registryAgents.isEmpty {
                Text("No agents found.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(configuration.registryAgents) { agent in
                        AgentRow(agent: agent, configuration: configuration)
                        if agent.id != configuration.registryAgents.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Wizard Templates

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chat Rules")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(WizardTemplateType.allCases) { type in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedTemplates.contains(type) },
                            set: { newValue in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if newValue {
                                        expandedTemplates.insert(type)
                                    } else {
                                        expandedTemplates.remove(type)
                                    }
                                }
                            }
                        )
                    ) {
                        templateEditor(for: type)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                    } label: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    if type != WizardTemplateType.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func templateEditor(for type: WizardTemplateType) -> some View {
        let binding = Binding<String>(
            get: { templateContents[type] ?? "" },
            set: {
                templateContents[type] = $0
                templateChanges.insert(type)
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: binding)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 200)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                if templateChanges.contains(type) {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button("Reset to Default", role: .destructive) {
                    showingResetConfirm = type
                }
                .buttonStyle(.plain)
                .font(.caption)

                Button("Save") {
                    saveTemplate(type)
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!templateChanges.contains(type))
            }
        }
        .confirmationDialog(
            "Reset \"\(type.displayName)\"?",
            isPresented: Binding(
                get: { showingResetConfirm == type },
                set: { if !$0 { showingResetConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reset to Default", role: .destructive) {
                templateManager.resetToDefault(type)
                loadTemplate(type)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your custom template with the default version.")
        }
    }

    // MARK: - Template Helpers

    private func loadAllTemplates() {
        for type in WizardTemplateType.allCases {
            loadTemplate(type)
        }
    }

    private func loadTemplate(_ type: WizardTemplateType) {
        if let template = templateManager.template(for: type) {
            templateContents[type] = template.content
        }
        templateChanges.remove(type)
    }

    private func saveTemplate(_ type: WizardTemplateType) {
        guard let content = templateContents[type] else { return }
        let template = WizardTemplate(
            type: type,
            content: content,
            lastModified: Date()
        )
        templateManager.save(template)
        templateChanges.remove(type)
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
            Toggle(agent.name, isOn: Binding(
                get: { configuration.isEnabled(agent.id) },
                set: { configuration.setEnabled(agent.id, $0) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    ACPSettingsView()
        .frame(width: 480)
}
