import SwiftUI
import SwiftData

struct RemoteServersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RemoteServer.label) private var servers: [RemoteServer]

    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remote Servers")
                .font(.headline)

            Text("Connect to remote servers to browse and edit skills via SSH. Requires key-based authentication.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(servers) { server in
                        ServerRow(server: server)
                        if server.id != servers.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(minHeight: 120)

            HStack {
                Spacer()
                Button("Add Server...") {
                    showingAddSheet = true
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            AddServerSheet()
        }
    }
}

// MARK: - Server Row

private struct ServerRow: View {
    @Bindable var server: RemoteServer
    @Environment(\.modelContext) private var modelContext
    @State private var isTesting = false
    @State private var isSyncing = false
    @State private var testResult: TestResult?
    @State private var syncLog: String?
    @State private var showingEditSheet = false

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.label)
                        .font(.body)
                    Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                    Text("Path: \(server.skillsBasePath)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fontDesign(.monospaced)
                    if let lastSync = server.lastSyncDate {
                        Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if let result = testResult {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Button {
                    testConnection()
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Test")
                    }
                }
                .disabled(isTesting)

                Button {
                    syncNow()
                } label: {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Sync")
                    }
                }
                .disabled(isSyncing)

                Button {
                    showingEditSheet = true
                } label: {
                    Text("Edit")
                }

                Button(role: .destructive) {
                    modelContext.delete(server)
                    try? modelContext.save()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            if let error = server.lastSyncError {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let log = syncLog {
                Text(log)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditServerSheet(server: server)
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                try await SSHService.testConnection(server)
                await MainActor.run {
                    testResult = .success
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func syncNow() {
        isSyncing = true
        syncLog = "Connecting to \(server.sshDestination)..."
        Task { @MainActor in
            do {
                let skills = try await SSHService.findSkills(server)
                if skills.isEmpty {
                    syncLog = "find returned 0 results.\nPath searched: \(server.skillsBasePath)\nCommand: find <path> -name 'SKILL.md' -type f"
                } else {
                    let scanner = SkillScanner(modelContext: modelContext)
                    await scanner.scanRemoteServer(server)
                    syncLog = "Found \(skills.count) skill(s):\n" + skills.map { "  \($0.path)" }.joined(separator: "\n")
                }
            } catch {
                syncLog = "Sync failed: \(error.localizedDescription)"
            }
            isSyncing = false
        }
    }
}

// MARK: - Add Server Sheet

private struct AddServerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var basePath = ""
    @State private var sshKeyPath = ""
    @State private var isTesting = false
    @State private var testPassed = false
    @State private var testError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Remote Server")
                .font(.headline)

            Form {
                TextField("Label", text: $label, prompt: Text("Production Server"))
                TextField("Host", text: $host, prompt: Text("192.168.1.100"))
                TextField("Port", text: $port, prompt: Text("22"))
                TextField("Username", text: $username, prompt: Text("root"))
                TextField("Base Path", text: $basePath, prompt: Text("e.g. ~/.openclaw, ~/skills"))
                TextField("SSH Key Path", text: $sshKeyPath, prompt: Text("Optional — e.g. ~/.ssh/id_ed25519"))
            }
            .formStyle(.grouped)

            if let testError {
                Text(testError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if testPassed {
                Label("Connection successful", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Test Connection") {
                    testConnection()
                }
                .disabled(host.isEmpty || username.isEmpty || isTesting)

                Button("Add") {
                    addServer()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(label.isEmpty || host.isEmpty || username.isEmpty || basePath.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func testConnection() {
        isTesting = true
        testPassed = false
        testError = nil

        let server = RemoteServer(
            label: label,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            skillsBasePath: basePath
        )
        server.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath

        Task {
            do {
                try await SSHService.testConnection(server)
                await MainActor.run {
                    testPassed = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testError = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }

    private func addServer() {
        let server = RemoteServer(
            label: label,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            skillsBasePath: basePath
        )
        server.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath
        modelContext.insert(server)
        try? modelContext.save()

        Task {
            let scanner = SkillScanner(modelContext: modelContext)
            await scanner.scanRemoteServer(server)
        }
    }
}

// MARK: - Edit Server Sheet

private struct EditServerSheet: View {
    @Bindable var server: RemoteServer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var label: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var username: String = ""
    @State private var basePath: String = ""
    @State private var sshKeyPath: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Server")
                .font(.headline)

            Form {
                TextField("Label", text: $label, prompt: Text("Production Server"))
                TextField("Host", text: $host, prompt: Text("192.168.1.100"))
                TextField("Port", text: $port, prompt: Text("22"))
                TextField("Username", text: $username, prompt: Text("root"))
                TextField("Base Path", text: $basePath, prompt: Text("e.g. ~/.openclaw, ~/skills"))
                TextField("SSH Key Path", text: $sshKeyPath, prompt: Text("Optional — e.g. ~/.ssh/id_ed25519"))
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    let connectionChanged = server.host != host
                        || server.username != username
                        || server.skillsBasePath != basePath
                        || server.port != (Int(port) ?? 22)

                    server.label = label
                    server.host = host
                    server.port = Int(port) ?? 22
                    server.username = username
                    server.skillsBasePath = basePath
                    server.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath

                    if connectionChanged {
                        // Purge stale skills — they may point to files on the old target
                        for skill in server.skills {
                            modelContext.delete(skill)
                        }
                    }

                    try? modelContext.save()
                    dismiss()

                    if connectionChanged {
                        Task {
                            let scanner = SkillScanner(modelContext: modelContext)
                            await scanner.scanRemoteServer(server)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(label.isEmpty || host.isEmpty || username.isEmpty || basePath.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            label = server.label
            host = server.host
            port = "\(server.port)"
            username = server.username
            basePath = server.skillsBasePath
            sshKeyPath = server.sshKeyPath ?? ""
        }
    }
}
