import SwiftUI

/// Settings for the source-of-truth directory used when symlinking library items.
struct LibrarySettingsView: View {
    @AppStorage("sotDir") private var sotDir = FileManager.default.homeDirectoryForCurrentUser.path + "/.fasttalk"
    @AppStorage("includePluginSkills") private var includePluginSkills = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Include plugin skills", isOn: $includePluginSkills)
                    .onChange(of: includePluginSkills) {
                        NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
                    }
                Text("When enabled, skills installed by Claude CLI and Claude Desktop plugins are listed in the library. These are read-only and managed by the plugin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return sotDir.hasPrefix(home) ? "~" + sotDir.dropFirst(home.count) : sotDir
    }
}

private struct DirectoryPickerRow: View {
    let label: String
    @Binding var path: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Choose...") {
                pickDirectory()
            }
        }
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Select"
        panel.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
    }
}
