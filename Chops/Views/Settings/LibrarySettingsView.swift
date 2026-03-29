import SwiftUI

struct LibrarySettingsView: View {
    @AppStorage("includePluginSkills") private var includePluginSkills = false
    @AppStorage("sharedLibraryPath") private var sharedLibraryPath = ""
    @AppStorage("sharedLibraryShowHidden") private var includeHiddenFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared Library")
                    .font(.headline)
                Text("A vendor-neutral directory (e.g. ~/.tools) whose skills, agents, and rules you can symlink into any installed tool.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Path, e.g. ~/.chops", text: $sharedLibraryPath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            sharedLibraryPath = normalize(sharedLibraryPath)
                            triggerRescan()
                        }
                    Button("Browse") { browseForSharedLibrary() }
                    Toggle("Hidden files", isOn: $includeHiddenFiles)
                        .controlSize(.small)
                }
                if !sharedLibraryPath.isEmpty {
                    Button("Clear") {
                        sharedLibraryPath = ""
                        triggerRescan()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Include plugin skills", isOn: $includePluginSkills)
                    .onChange(of: includePluginSkills) { triggerRescan() }
                Text("When enabled, skills installed by Claude CLI and Claude Desktop plugins are listed in the library. These are read-only and managed by the plugin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func triggerRescan() {
        NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
    }

    private func normalize(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func browseForSharedLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = includeHiddenFiles
        panel.title = "Choose Shared Library Directory"
        if panel.runModal() == .OK, let url = panel.url {
            sharedLibraryPath = normalize(url.path)
            triggerRescan()
        }
    }
}
