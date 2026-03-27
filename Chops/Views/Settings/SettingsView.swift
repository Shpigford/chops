import SwiftUI
import Sparkle

extension Notification.Name {
    static let customScanPathsChanged = Notification.Name("customScanPathsChanged")
}

struct SettingsView: View {
    let updater: SPUUpdater
    @State private var customPaths: [String] = []
    @State private var defaultTool: ToolSource = .claude

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("settings.general".localized, systemImage: "gearshape")
                }

            scanSettings
                .tabItem {
                    Label("settings.scanDirectories".localized, systemImage: "folder.badge.gearshape")
                }

            RemoteServersSettingsView()
                .tabItem {
                    Label("settings.servers".localized, systemImage: "server.rack")
                }

            aboutView
                .tabItem {
                    Label("settings.about".localized, systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 380)
        .onAppear {
            loadCustomPaths()
        }
    }

    private var generalSettings: some View {
        Form {
            Picker("settings.defaultTool".localized, selection: $defaultTool) {
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
            Text("settings.customScanDirectories".localized)
                .font(.headline)

            Text("settings.scanDescription".localized)
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
                Button("settings.addDirectory".localized) {
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

            Text("settings.appName".localized)
                .font(.title)
                .fontWeight(.bold)

            Text("settings.version".localized(appVersionParts.version, appVersionParts.build))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("settings.tagline".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("settings.checkForUpdates".localized) {
                    updater.checkForUpdates()
                }

                Button("settings.website".localized) {
                    NSWorkspace.shared.open(URL(string: "https://chops.md")!)
                }

                Button("settings.twitter".localized) {
                    NSWorkspace.shared.open(URL(string: "https://x.com/Shpigford")!)
                }

                Button("settings.github".localized) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Shpigford/chops")!)
                }
            }

            Text("settings.license".localized)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersionParts: (version: String, build: String) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return (version, build)
    }

    private var appVersion: String {
        let parts = appVersionParts
        return "\(parts.version) (\(parts.build))"
    }

    private func loadCustomPaths() {
        customPaths = UserDefaults.standard.stringArray(forKey: "customScanPaths") ?? []
    }

    private func saveCustomPaths() {
        UserDefaults.standard.set(customPaths, forKey: "customScanPaths")
        NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
    }
}
