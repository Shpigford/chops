import SwiftUI

extension Notification.Name {
    static let customScanPathsChanged = Notification.Name("customScanPathsChanged")
}

// MARK: - Settings Tab Definition

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, library, aiAssist, scanDirs, servers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .library: "Library"
        case .aiAssist: "AI Assist"
        case .scanDirs: "Scan Directories"
        case .servers: "Servers"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .library: "books.vertical"
        case .aiAssist: "sparkles"
        case .scanDirs: "folder.badge.gearshape"
        case .servers: "server.rack"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    private static let logger = AppLogger.settings

    @AppStorage("settingsSelectedTab") private var selectedTab: SettingsTab = .general
    @State private var customPaths: [String] = []
    @AppStorage("defaultTool") private var defaultTool: ToolSource = .claude

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 1) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsTabButton(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Tab content — each pane sizes itself, no outer ScrollView
            tabContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loadCustomPaths()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalSettings
        case .library:
            LibrarySettingsView()
        case .aiAssist:
            ACPSettingsView()
        case .scanDirs:
            scanSettings
        case .servers:
            RemoteServersSettingsView()
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)

            Picker("Default tool", selection: $defaultTool) {
                ForEach(ToolSource.allCases) { tool in
                    Text(tool.displayName).tag(tool)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300)
        }
        .padding()
    }

    private var scanSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Scan Directories")
                .font(.headline)

            Text("Add a parent directory (e.g. ~/Development) and Fast Talk will scan each project inside it for tool-specific skills and agents.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !customPaths.isEmpty {
                VStack(spacing: 0) {
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
                                    .symbolRenderingMode(.multicolor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(path)")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)

                        if path != customPaths.last {
                            Divider()
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("No custom directories added.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

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
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private func loadCustomPaths() {
        customPaths = UserDefaults.standard.stringArray(forKey: "customScanPaths") ?? []
    }

    private func saveCustomPaths() {
        UserDefaults.standard.set(customPaths, forKey: "customScanPaths")
        NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
    }
}

// MARK: - Tab Button

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.title3)
                    .frame(height: 20)
                Text(tab.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
