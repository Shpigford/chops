import SwiftUI
import Sparkle

extension Notification.Name {
    static let customScanPathsChanged = Notification.Name("customScanPathsChanged")
}

struct SettingsView: View {
    private static let logger = AppLogger.settings

    let updater: SPUUpdater
    @State private var customPaths: [String] = []
    @AppStorage("defaultTool") private var defaultTool: ToolSource = .claude

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            LibrarySettingsView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            ACPSettingsView()
                .tabItem {
                    Label("AI Assist", systemImage: "sparkles")
                }

            scanSettings
                .tabItem {
                    Label("Scan Directories", systemImage: "folder.badge.gearshape")
                }

            RemoteServersSettingsView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }

            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 480, maxWidth: 480, minHeight: 300)
        .onAppear {
            loadCustomPaths()
        }
    }

    private var generalSettings: some View {
        Form {
            Picker("Default tool", selection: $defaultTool) {
                ForEach(ToolSource.allCases) { tool in
                    Text(tool.displayName).tag(tool)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var scanSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Scan Directories")
                .font(.headline)

            Text("Add a parent directory (e.g. ~/Development) and Chops will scan each project inside it for tool-specific skills and agents.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(customPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            customPaths.removeAll { $0 == path }
                            saveCustomPaths()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 120)

            HStack {
                Spacer()
                Button("Add Directory...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        let path = url.path
                        if !customPaths.contains(path) {
                            customPaths.append(path)
                            saveCustomPaths()
                        }
                    }
                }
            }
        }
        .padding()
    }

    private var aboutView: some View {
        VStack(spacing: 16) {
            Image("tool-claude") // App icon from asset catalog
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .opacity(0) // Hidden — use the actual app icon instead
                .overlay {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                    }
                }

            Text("Chops")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Your AI skills and agents, finally organized.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("Check for Updates") {
                    updater.checkForUpdates()
                }

                Button("Website") {
                    if let url = URL(string: "https://chops.md") { NSWorkspace.shared.open(url) }
                }

                Button("@Shpigford") {
                    if let url = URL(string: "https://x.com/Shpigford") { NSWorkspace.shared.open(url) }
                }

                Button("GitHub") {
                    if let url = URL(string: "https://github.com/Shpigford/chops") { NSWorkspace.shared.open(url) }
                }
            }

            Text("Free and open source under the MIT License.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func loadCustomPaths() {
        customPaths = UserDefaults.standard.stringArray(forKey: "customScanPaths") ?? []
    }

    private func saveCustomPaths() {
        UserDefaults.standard.set(customPaths, forKey: "customScanPaths")
        NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
    }
}
