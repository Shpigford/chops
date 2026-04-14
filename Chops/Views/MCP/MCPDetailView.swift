import SwiftUI
import SwiftData

struct MCPDetailView: View {
    @Bindable var server: MCPServer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                connectionSection
                if !server.env.isEmpty {
                    Divider()
                    envSection
                }
                if !server.headers.isEmpty {
                    Divider()
                    headersSection
                }
                Divider()
                sourceSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(server.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NSWorkspace.shared.selectFile(
                        server.configFilePath,
                        inFileViewerRootedAtPath: ""
                    )
                } label: {
                    Label("Show Config File", systemImage: "doc.text.magnifyingglass")
                }
                .help("Reveal config file in Finder")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            ToolIcon(tool: server.toolSource, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Text(server.toolSource.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(server.displayTransport)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(transportColor, in: RoundedRectangle(cornerRadius: 4))

                    if !server.isEnabled {
                        Text("Disabled")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.headline)

            if server.transportType == "stdio" {
                configRow(label: "Command", value: server.command ?? "—")
                if !server.args.isEmpty {
                    configRow(label: "Arguments", value: server.args.joined(separator: " "))
                }
            } else {
                configRow(label: "URL", value: server.url ?? "—")
            }
        }
    }

    @ViewBuilder
    private var envSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Environment")
                .font(.headline)

            ForEach(server.env.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                configRow(label: key, value: maskedValue(value))
            }
        }
    }

    @ViewBuilder
    private var headersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Headers")
                .font(.headline)

            ForEach(server.headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                configRow(label: key, value: maskedValue(value))
            }
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source")
                .font(.headline)

            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let displayPath = server.configFilePath.replacingOccurrences(of: home, with: "~")
            configRow(label: "Config File", value: displayPath)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func configRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private var transportColor: Color {
        switch server.transportType {
        case "stdio": .blue
        case "http": .green
        case "sse": .orange
        default: .gray
        }
    }

    private func maskedValue(_ value: String) -> String {
        let lowerValue = value.lowercased()
        let sensitivePatterns = ["key", "token", "secret", "password", "auth", "bearer"]
        let looksSecret = sensitivePatterns.contains { lowerValue.contains($0) }
            || (value.count > 20 && !value.contains("/") && !value.contains(" "))

        if looksSecret && value.count > 8 {
            let prefix = String(value.prefix(4))
            return "\(prefix)••••••••"
        }
        return value
    }
}
