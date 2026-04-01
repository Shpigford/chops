import SwiftUI
import SwiftData

/// Collapsible panel for linking/unlinking a skill, agent, or rule to vendor directories.
struct VendorLinkingPanel: View {
    let skill: Skill
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = false
    @State private var errorMessage: String?
    @State private var showingError = false

    @Query private var allSymlinks: [SymlinkTarget]

    private var linkedToolRawValues: Set<String> {
        Set(allSymlinks
            .filter { $0.skillResolvedPath == skill.resolvedPath && !$0.isBroken }
            .map(\.toolSource))
    }

    private var eligibleTools: [ToolSource] {
        ToolSource.allCases.filter { tool in
            guard tool.isInstalled else { return false }
            let dirs = tool.globalDirs(for: skill.itemKind)
            let hasRecord = linkedToolRawValues.contains(tool.rawValue)

            // Always include if there's an existing link — lets the user unlink even when
            // the tool has no configured dirs for this kind.
            guard !dirs.isEmpty || hasRecord else { return false }

            let isOrigin = dirs.contains { skill.resolvedPath.hasPrefix($0 + "/") }

            // Exclude the origin tool (skill physically lives there) unless a record exists (allows unlinking).
            if isOrigin && !hasRecord { return false }

            // Vendor-origin skills must not link to Shared (only unlink if a stale record exists).
            if tool == .shared && !isOrigin && !hasRecord { return false }

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
                        ForEach(tools) { tool in
                            VendorLinkRow(
                                skill: skill,
                                tool: tool,
                                initiallyLinked: linkedToolRawValues.contains(tool.rawValue),
                                onError: { msg in
                                    errorMessage = msg
                                    showingError = true
                                }
                            )
                            if tool.id != tools.last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .alert("Link Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

}

private struct VendorLinkRow: View {
    let skill: Skill
    let tool: ToolSource
    let initiallyLinked: Bool
    let onError: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var linked: Bool
    @State private var linkedPath: String?
    @State private var isSyncingFromParent = false

    init(
        skill: Skill,
        tool: ToolSource,
        initiallyLinked: Bool,
        onError: @escaping (String) -> Void
    ) {
        self.skill = skill
        self.tool = tool
        self.initiallyLinked = initiallyLinked
        self.onError = onError
        self._linked = State(initialValue: initiallyLinked)
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
        .onChange(of: initiallyLinked) { _, newValue in
            guard linked != newValue else { return }
            isSyncingFromParent = true
            linked = newValue
            refreshLinkedPath()
        }
        .onChange(of: linked) { _, newValue in
            guard !isSyncingFromParent else {
                isSyncingFromParent = false
                return
            }
            do {
                if newValue {
                    try SymlinkService.shared.link(skill, to: tool, context: modelContext)
                } else {
                    try SymlinkService.shared.unlink(skill, from: tool, context: modelContext)
                }
                refreshLinkedPath()
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
