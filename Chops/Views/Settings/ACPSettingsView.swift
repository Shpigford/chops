import SwiftUI
import UniformTypeIdentifiers

struct ACPSettingsView: View {
    @State private var configuration = ACPConfiguration.shared

    var body: some View {
        Form {
            Section {
                Text("Configure AI assistants to help compose and improve skills, agents, and rules.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(ACPConfiguration.supportedTools, id: \.self) { tool in
                if let config = configuration.config(for: tool) {
                    ACPToolConfigSection(
                        tool: tool,
                        config: Binding(
                            get: { config },
                            set: { configuration.updateConfig($0) }
                        )
                    )
                }
            }

            Section {
                Button("Reset to Defaults") {
                    configuration.resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Tool Config Section

struct ACPToolConfigSection: View {
    let tool: ToolSource
    @Binding var config: ACPToolConfig
    @State private var showFilePicker = false

    private var statusColor: Color {
        if !config.enabled { return .secondary }
        return config.isValid ? .green : .red
    }

    private var statusText: String {
        if !config.enabled { return "Disabled" }
        if config.binaryPath.isEmpty { return "Not configured" }
        return config.isValid ? "Ready" : "Binary not found"
    }

    var body: some View {
        Section {
            Toggle("Enabled", isOn: $config.enabled)

            if config.enabled {
                HStack {
                    TextField("Binary path", text: $config.binaryPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        showFilePicker = true
                    }
                }

                TextField("Flags", text: $config.flags)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack(spacing: 8) {
                ToolIcon(tool: tool, size: 16)
                Text(tool.displayName)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.unixExecutable, .executable, .item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                config.binaryPath = url.path
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ACPSettingsView()
        .frame(width: 500, height: 600)
}
