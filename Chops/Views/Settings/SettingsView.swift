import SwiftUI
import SwiftData
import Sparkle

extension Notification.Name {
    static let customScanPathsChanged = Notification.Name("customScanPathsChanged")
}

struct SettingsView: View {
    private static let logger = AppLogger.settings

    let updater: SPUUpdater
    @Environment(\.modelContext) private var modelContext
    @State private var customPaths: [String] = []
    @State private var defaultTool: ToolSource = .claude
    @State private var showingClearConfirmation = false
    @AppStorage("globalSourcePath") private var globalSourcePath = ""
    @AppStorage("registryEnabled") private var registryEnabled = false
    @AppStorage("registryURL") private var registryURL = "https://skills.sh/api/search"
    @AppStorage("scanClaudePlugins") private var scanClaudePlugins = false
    @AppStorage("hiddenTools") private var hiddenToolsRaw = ""

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            toolsSettings
                .tabItem {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }

            ACPSettingsView()
                .tabItem {
                    Label("AI Assist", systemImage: "sparkles")
                }

            scanSettings
                .tabItem {
                    Label("Scan Directories", systemImage: "folder.badge.gearshape")
                }

            registrySettings
                .tabItem {
                    Label("Registry", systemImage: "globe")
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
        .frame(minWidth: 480, minHeight: 550, idealHeight: 600)
        .onAppear {
            loadCustomPaths()
        }
    }

    private var generalSettings: some View {
        Form {
            Picker("Default tool for new skills", selection: $defaultTool) {
                ForEach(ToolSource.allCases) { tool in
                    Text(tool.displayName).tag(tool)
                }
            }
            
            Section("Global Path") {
                HStack {
                    TextField("", text: $globalSourcePath, prompt: Text("~/.aidevtools"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            globalSourcePath = url.path
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Text("Source of truth for agents, skills, and rules. Default: ~/.aidevtools")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Plugins") {
                Toggle("Scan Claude Plugin Skills", isOn: $scanClaudePlugins)
                
                Text("Include skills from Claude CLI plugins (~/.claude/plugins/installed_plugins.json)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Maintenance") {
                Button("Clear Database & Rescan") {
                    showingClearConfirmation = true
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                
                Text("Delete all cached skill data and rescan from disk. Use this if categories or tool sources appear incorrect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Clear Database?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear & Rescan", role: .destructive) {
                clearAndRescan()
            }
        } message: {
            Text("This will delete all cached skill data and rescan from disk. Your actual skill files will not be affected.")
        }
    }

    private var hiddenTools: Set<ToolSource> {
        get {
            Set(hiddenToolsRaw.split(separator: ",").compactMap { ToolSource(rawValue: String($0)) })
        }
    }

    private func setToolHidden(_ tool: ToolSource, hidden: Bool) {
        var tools = hiddenTools
        if hidden {
            tools.insert(tool)
        } else {
            tools.remove(tool)
        }
        hiddenToolsRaw = tools.map(\.rawValue).sorted().joined(separator: ",")
    }

    private var toolsSettings: some View {
        Form {
            Section {
                Text("Select which tools appear in the sidebar. Hidden tools will still be scanned but won't show in the filter list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Visible Tools") {
                ForEach(ToolSource.allCases.filter(\.listable), id: \.self) { tool in
                    Toggle(isOn: Binding(
                        get: { !hiddenTools.contains(tool) },
                        set: { visible in setToolHidden(tool, hidden: !visible) }
                    )) {
                        HStack(spacing: 8) {
                            ToolIcon(tool: tool, size: 16)
                            Text(tool.displayName)
                        }
                    }
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

            Text("Add a parent directory (e.g. ~/Development) and Chops will scan each project inside it for tool-specific skills.")
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

    private var registrySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable Skills Registry", isOn: $registryEnabled)
                .font(.body)

            if registryEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Registry URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://skills.sh/api/search", text: $registryURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text("Point this to a self-hosted registry or leave it as the default.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("Privacy Notice", systemImage: "lock.shield")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("When enabled, search queries typed in the Browse Registry sheet are sent to the registry URL above. The service operator may log search terms and IP addresses. Disable to prevent all external requests from the registry feature.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
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

            Text("Your AI agent skills, finally organized.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("Check for Updates") {
                    updater.checkForUpdates()
                }

                if let websiteURL = URL(string: "https://chops.md") {
                    Button("Website") {
                        NSWorkspace.shared.open(websiteURL)
                    }
                }

                if let twitterURL = URL(string: "https://x.com/Shpigford") {
                    Button("@Shpigford") {
                        NSWorkspace.shared.open(twitterURL)
                    }
                }

                if let githubURL = URL(string: "https://github.com/Shpigford/chops") {
                    Button("GitHub") {
                        NSWorkspace.shared.open(githubURL)
                    }
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
    
    private func clearAndRescan() {
        do {
            let descriptor = FetchDescriptor<Skill>()
            let allSkills = try modelContext.fetch(descriptor)
            for skill in allSkills {
                modelContext.delete(skill)
            }

            let collectionDescriptor = FetchDescriptor<SkillCollection>()
            let allCollections = try modelContext.fetch(collectionDescriptor)
            for collection in allCollections {
                modelContext.delete(collection)
            }

            try modelContext.save()

            NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
            Self.logger.info("Database cleared successfully, triggering rescan")
        } catch {
            Self.logger.error("Failed to clear database: \(error.localizedDescription)")
        }
    }
}
