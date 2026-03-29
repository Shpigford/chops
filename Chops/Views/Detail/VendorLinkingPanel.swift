import SwiftUI
import SwiftData

/// Collapsible panel for linking/unlinking a skill to vendor directories.
struct VendorLinkingPanel: View {
    let skill: Skill
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = false
    @State private var linkedToolRawValues: Set<String> = []
    @State private var errorMessage: String?
    @State private var showingError = false

    private var eligibleTools: [ToolSource] {
        ToolSource.allCases.filter { tool in
            guard tool.isInstalled else { return false }
            let dirs = tool.globalDirs(for: skill.itemKind)
            guard !dirs.isEmpty else { return false }

            let isOrigin = dirs.contains { skill.resolvedPath.hasPrefix($0 + "/") || skill.resolvedPath.hasPrefix($0) }
            let isHost = skill.toolSources.contains(tool)
            let hasRecord = linkedToolRawValues.contains(tool.rawValue)

            // Exclude origin and host unless there's already a record (allows unlinking).
            if (isOrigin || isHost) && !hasRecord { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Vendor Links")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                let tools = eligibleTools
                if tools.isEmpty {
                    Text("No other installed vendors support \(skill.itemKind.displayName.lowercased()).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                            VendorLinkRow(
                                skill: skill,
                                tool: tool,
                                initiallyLinked: linkedToolRawValues.contains(tool.rawValue),
                                onError: { msg in
                                    errorMessage = msg
                                    showingError = true
                                },
                                onChanged: { refreshLinkedTools() }
                            )
                            if index < tools.count - 1 {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .onAppear { refreshLinkedTools() }
        .alert("Link Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refreshLinkedTools() {
        linkedToolRawValues = Set(
            SymlinkService.shared.targets(for: skill, context: modelContext).map(\.toolSource)
        )
    }
}

private struct VendorLinkRow: View {
    let skill: Skill
    let tool: ToolSource
    let onError: (String) -> Void
    let onChanged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var linked: Bool
    @State private var linkedPath: String?

    init(
        skill: Skill,
        tool: ToolSource,
        initiallyLinked: Bool,
        onError: @escaping (String) -> Void,
        onChanged: @escaping () -> Void
    ) {
        self.skill = skill
        self.tool = tool
        self.onError = onError
        self.onChanged = onChanged
        self._linked = State(initialValue: initiallyLinked)
        self._linkedPath = State(initialValue: nil)
    }

    var body: some View {
        HStack(spacing: 8) {
            ToolIcon(tool: tool)
                .frame(width: 20, height: 20)

            Text(tool.displayName)
                .font(.caption)
                .fixedSize()

            PathCrumb(source: skill.resolvedPath, destination: linked ? linkedPath : nil)

            Spacer(minLength: 4)

            Toggle("", isOn: $linked)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .onAppear { refreshLinkedPath() }
        .onChange(of: linked) { _, newValue in
            do {
                if newValue {
                    try SymlinkService.shared.link(skill, to: tool, context: modelContext)
                } else {
                    try SymlinkService.shared.unlink(skill, from: tool, context: modelContext)
                }
                refreshLinkedPath()
                onChanged()
            } catch {
                linked = !newValue
                onError(error.localizedDescription)
            }
        }
    }

    private func refreshLinkedPath() {
        linkedPath = SymlinkService.shared.targets(for: skill, context: modelContext)
            .first { $0.toolSource == tool.rawValue }
            .map(\.linkedPath)
    }
}

/// Single-line path display: `~/src/file.md` or `~/src/file.md → ~/dst/file.md`
private struct PathCrumb: View {
    let source: String
    let destination: String?

    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    private func tilde(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(tilde(source))
                .lineLimit(1)
                .truncationMode(.middle)
            if let dst = destination {
                Text("→")
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                Text(tilde(dst))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
    }
}
