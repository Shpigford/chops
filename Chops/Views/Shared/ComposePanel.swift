import SwiftUI

/// Inline panel for composing/editing skill content via the user's installed Claude or Codex.
struct ComposePanel: View {
    private struct DiffApplyError: Identifiable {
        let id = UUID()
        let message: String
    }

    @Binding var content: String
    @Binding var isVisible: Bool
    let skillName: String
    let skillDescription: String
    let frontmatter: [String: String]
    /// Absolute path of the file being edited — used to read source-of-truth from disk.
    let filePath: String
    let workingDirectory: URL
    /// Called after a diff is accepted — use to persist the change immediately.
    let onAccept: () -> Void

    @State private var selectedTemplateType: WizardTemplateType
    @State private var inputText = ""
    @AppStorage("AgentSelectedId") private var selectedAgentId: String?
    @State private var agent: (any AgentSession)?
    @State private var showingDebugLogs = false

    /// Completed conversation history. Never holds in-flight messages — the agent drives live state.
    @State private var messages: [ChatMessage] = []
    /// True until the first successful prompt in this session.
    @State private var isFirstTurn = true

    @AppStorage("AgentDebugLogging") private var debugLoggingEnabled = false
    @State private var panelHeight: CGFloat = ComposeConstants.defaultPanelHeight
    @State private var isDragging = false
    @State private var dragStartHeight: CGFloat?
    @State private var applyingDiffID: String?
    @State private var diffApplyError: DiffApplyError?

    private static let minPanelHeight: CGFloat = 160
    private static let maxPanelHeight: CGFloat = 700

    init(
        content: Binding<String>,
        isVisible: Binding<Bool>,
        skillName: String,
        skillDescription: String = "",
        frontmatter: [String: String] = [:],
        filePath: String,
        workingDirectory: URL,
        templateType: WizardTemplateType,
        onAccept: @escaping () -> Void = {}
    ) {
        self._content = content
        self._isVisible = isVisible
        self.skillName = skillName
        self.skillDescription = skillDescription
        self.frontmatter = frontmatter
        self.filePath = filePath
        self.workingDirectory = workingDirectory
        self.onAccept = onAccept
        self._selectedTemplateType = State(initialValue: templateType)
    }

    private var configuredAgents: [AgentID] { AgentConfiguration.shared.enabledAgents }
    private var selectedAgent: AgentID? { selectedAgentId.flatMap(AgentID.init(rawValue:)) }

    private var isConnected: Bool { agent?.isConnected ?? false }
    private var isConnecting: Bool { agent?.isConnecting ?? false }
    private var isProcessing: Bool { agent?.isProcessing ?? false }
    private var hasPendingDiffs: Bool { messages.contains { $0.diffs.contains { $0.status == .pending } } }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle

            if configuredAgents.isEmpty {
                noToolsConfiguredView
            } else if !isConnected && messages.isEmpty {
                agentPickerEmptyState
            } else {
                VStack(spacing: 0) {
                    topBar
                    Divider()
                    chatArea
                    Divider()
                    inputArea
                }
            }
        }
        .frame(height: panelHeight)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            if selectedAgentId == nil {
                selectedAgentId = configuredAgents.first?.rawValue
            }
        }
        .onDisappear {
            forceDisconnect()
        }
        .onChange(of: selectedAgentId) { _, _ in
            forceDisconnect()
        }
        .onChange(of: configuredAgents.map(\.rawValue)) { _, newIds in
            if selectedAgentId == nil || !newIds.contains(selectedAgentId ?? "") {
                selectedAgentId = newIds.first
            }
        }
        .sheet(isPresented: Binding(
            get: { agent?.pendingPermissionRequest != nil },
            set: { if !$0 { agent?.respondToPermission(optionId: nil) } }
        )) {
            if let request = agent?.pendingPermissionRequest {
                permissionSheet(request: request)
            }
        }
        .alert(item: $diffApplyError) { error in
            Alert(
                title: Text("Apply Failed"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func permissionSheet(request: PermissionRequest) -> some View {
        if let diff = request.diffPreview {
            // Pre-flight diff approval. The agent has NOT touched the file yet — clicking
            // Approve writes it, clicking Reject leaves disk untouched.
            diffPermissionSheet(request: request, diff: diff)
        } else {
            simplePermissionSheet(request: request)
        }
    }

    @ViewBuilder
    private func simplePermissionSheet(request: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Permission Required", systemImage: "hand.raised.fill")
                .font(.headline)
            Text(request.title)
                .foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(request.options, id: \.optionId) { option in
                    Button(option.name) {
                        agent?.respondToPermission(optionId: option.optionId)
                    }
                    .buttonStyle(.bordered)
                    .tint(permissionOptionTint(for: option.kind))
                }
            }
            Divider()
            Button("Cancel") {
                agent?.respondToPermission(optionId: nil)
            }
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 320, maxWidth: 440)
    }

    @ViewBuilder
    private func diffPermissionSheet(request: PermissionRequest, diff: PermissionDiffPreview) -> some View {
        let fileName = URL(fileURLWithPath: diff.path).lastPathComponent
        let approveOption = request.options.first { $0.kind.hasPrefix("allow") }
        let rejectOption = request.options.first { $0.kind.hasPrefix("reject") }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: diff.existedBefore ? "pencil.line" : "doc.badge.plus")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title)
                        .font(.headline)
                    Text(diff.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            DiffReviewPanel(
                original: diff.originalText ?? "",
                proposed: diff.proposedText,
                onAccept: {
                    agent?.respondToPermission(optionId: approveOption?.optionId)
                },
                onReject: {
                    agent?.respondToPermission(optionId: rejectOption?.optionId)
                },
                isApplying: false
            )
            .frame(minHeight: 320, idealHeight: 420, maxHeight: 540)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

            HStack {
                Spacer()
                Button("Cancel") {
                    agent?.respondToPermission(optionId: nil)
                }
                .keyboardShortcut(.cancelAction)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 820, maxWidth: 1100)
        .accessibilityLabel("Approve change to \(fileName)")
    }

    private func permissionOptionTint(for kind: String) -> Color {
        switch kind {
        case "allow_once", "allow_always": return .green
        case "reject_once", "reject_always": return .red
        default: return .secondary
        }
    }

    // MARK: - Views

    @Environment(\.openSettings) private var openSettings

    private var agentPickerEmptyState: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Choose an agent to get started")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedAgentId) {
                    Text("Select agent…").tag(nil as String?)
                    ForEach(configuredAgents) { agentId in
                        Text(agentId.displayName).tag(Optional(agentId.rawValue))
                    }
                }
                .labelsHidden()
                .fixedSize()
                connectControlsForSelectedAgent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            closeButton
                .padding(12)
        }
    }

    /// Connect / Connecting / Install controls for the currently-selected agent.
    @ViewBuilder
    private var connectControlsForSelectedAgent: some View {
        if let agentId = selectedAgent {
            if isConnecting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Connecting…")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else if agentId.toolSource.cliBinaryURL == nil {
                VStack(spacing: 8) {
                    Text("\(agentId.displayName) isn't installed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link(destination: agentId.installURL) {
                        Label("Install \(agentId.displayName)", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            } else if let error = agent?.lastError {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                    Button {
                        connect()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .frame(maxWidth: 360)
            } else {
                Button {
                    connect()
                } label: {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    private var noToolsConfiguredView: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Enable an agent to get started")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(AgentConfiguration.shared.supported) { agentId in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(agentId.displayName)
                                    .font(.callout.weight(.medium))
                                Text(agentId.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { AgentConfiguration.shared.isEnabled(agentId) },
                                set: { AgentConfiguration.shared.setEnabled(agentId, $0) }
                            ))
                            .labelsHidden()
                            .disabled(agentId.toolSource.cliBinaryURL == nil)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            closeButton
                .padding(12)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            // LEFT: Tool picker + connection + debug
            HStack(spacing: 8) {
                Picker("", selection: $selectedAgentId) {
                    Text("Select...").tag(nil as String?)
                    ForEach(configuredAgents) { agentId in
                        Text(agentId.displayName).tag(Optional(agentId.rawValue))
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                connectionButton
                debugLogButton
            }

            Spacer()

            // Error indicator — connection errors reported by the agent.
            if let error = agent?.lastError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                .frame(maxWidth: 200)
            }

            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Chat Area

    /// Completed messages worth showing — assistant turns with no text and no diffs are omitted.
    private var visibleMessages: [ChatMessage] {
        messages.filter { msg in
            guard msg.role == .assistant else { return true }
            return !msg.text.isEmpty || msg.isError || !msg.diffs.isEmpty
        }
    }

    private var chatArea: some View {
        GeometryReader { geo in
            let bubbleWidth = max(200, floor(geo.size.width * ComposeConstants.bubbleWidthRatio))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty && !isProcessing {
                            if isConnected {
                                connectedPlaceholder
                                    .frame(height: geo.size.height - 24)
                            } else {
                                disconnectedPlaceholder
                                    .frame(height: geo.size.height - 24)
                            }
                        }
                        ForEach(visibleMessages) { message in
                            chatRow(message: message, bubbleWidth: bubbleWidth)
                                .id(message.id)
                        }
                        // Live assistant bubble — reads directly from the SDK while prompt is active.
                        if isProcessing {
                            liveAssistantRow(bubbleWidth: bubbleWidth)
                                .id("live-assistant")
                        }
                    }
                    .padding(12)
                }
                .background(Color(.textBackgroundColor).opacity(0.3))
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("live-assistant", anchor: .bottom) }
                }
                .onChange(of: isProcessing) { _, active in
                    if active {
                        withAnimation { proxy.scrollTo("live-assistant", anchor: .bottom) }
                    } else if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: agent?.currentActivity) { _, _ in
                    if isProcessing {
                        withAnimation { proxy.scrollTo("live-assistant", anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var disconnectedPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Connect to start editing with AI")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                connect()
            } label: {
                Label("Connect", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectedPlaceholder: some View {
        VStack(spacing: 8) {
            Text("Describe what you'd like to change")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("The agent will edit this skill based on your instructions")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Live Assistant Row (SDK-driven, shown while prompt is active)

    @ViewBuilder
    private func liveAssistantRow(bubbleWidth: CGFloat) -> some View {
        let thoughtText = agent?.thoughtText ?? ""
        let responseText = agent?.responseText ?? ""
        let displayText = agent?.conversationalText(from: responseText) ?? responseText
        let waitingOnUser = agent?.pendingPermissionRequest != nil
        let activities = agent?.activities ?? []

        VStack(alignment: .leading, spacing: 6) {
            if !thoughtText.isEmpty {
                ThinkingView(text: thoughtText, isStreaming: true)
                    .frame(maxWidth: bubbleWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").foregroundStyle(.secondary)
                    Text("Agent").foregroundStyle(.secondary)
                    Spacer()
                    elapsedTurnLabel
                    inlineStopButton
                }
                .font(.caption)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)

                Divider().padding(.horizontal, 8)

                if !displayText.isEmpty {
                    Text(displayText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                }

                if !activities.isEmpty {
                    activityFeed(activities, waitingOnUser: waitingOnUser)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                } else if displayText.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(waitingOnUser ? "Waiting for your approval" : "Working…")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
            }
            .frame(maxWidth: bubbleWidth, alignment: .leading)
            .background(Color.primary.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
    }

    @ViewBuilder
    private func activityFeed(_ activities: [AgentActivity], waitingOnUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(activities) { activity in
                ActivityRow(activity: activity)
            }
            if waitingOnUser {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 14, alignment: .center)
                    Text("Waiting for your approval")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Spacer()
                }
            }
        }
    }

    private func liveStatusText(activity: String?, waitingOnUser: Bool) -> String {
        if waitingOnUser {
            return "Waiting for your approval"
        }
        return activity ?? "Working…"
    }

    /// Ticks every second while a turn is in flight so the elapsed-time label updates.
    @ViewBuilder
    private var elapsedTurnLabel: some View {
        if let started = agent?.turnStartedAt {
            TimelineView(.periodic(from: started, by: 1.0)) { ctx in
                Text(formatElapsed(from: started, to: ctx.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var inlineStopButton: some View {
        if isProcessing {
            Button {
                agent?.cancelPrompt()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .help("Stop this turn (⌘.)")
        }
    }

    private func formatElapsed(from start: Date, to now: Date) -> String {
        let s = Int(now.timeIntervalSince(start))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        return "\(m)m \(r)s"
    }

    // MARK: - Completed Message Rows

    @ViewBuilder
    private func chatRow(message: ChatMessage, bubbleWidth: CGFloat) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            switch message.role {
            case .user:
                HStack(spacing: 0) {
                    Spacer(minLength: 16)
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: bubbleWidth, alignment: .trailing)
                }
            case .assistant:
                if !message.thoughtText.isEmpty {
                    ThinkingView(text: message.thoughtText, isStreaming: false)
                        .frame(maxWidth: bubbleWidth, alignment: .leading)
                }
                assistantCard(message: message)
                    .frame(maxWidth: bubbleWidth, alignment: .leading)
            }
            ForEach(message.diffs.indices, id: \.self) { i in
                diffCard(messageId: message.id, diffIndex: i, diff: message.diffs[i])
            }
        }
    }

    @ViewBuilder
    private func assistantCard(message: ChatMessage) -> some View {
        let displayText = message.text

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if message.isError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Error").foregroundStyle(.orange)
                } else {
                    Image(systemName: "sparkles").foregroundStyle(.secondary)
                    Text("Agent").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()
                .padding(.horizontal, 8)

            if message.isError {
                Text(displayText)
                    .font(.body.italic())
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else if !displayText.isEmpty {
                MarkdownMessageView(text: displayText)
                    .font(.body)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Use a primary-relative tint so the card is visibly distinct from the window
        // background in both light and dark mode (controlBackgroundColor is too similar).
        .background(message.isError ? Color.orange.opacity(0.08) : Color.primary.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(message.isError ? Color.orange.opacity(0.35) : Color.secondary.opacity(0.2))
        )
    }

    @ViewBuilder
    private func diffCard(messageId: UUID, diffIndex: Int, diff: ChatDiff) -> some View {
        switch diff.status {
        case .accepted:
            HStack(spacing: 6) {
                Label("Changes accepted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("· \(diff.path.split(separator: "/").last.map(String.init) ?? diff.path)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
        case .rejected:
            HStack(spacing: 6) {
                Label("Changes rejected", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                Text("· \(diff.path.split(separator: "/").last.map(String.init) ?? diff.path)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
        case .pending:
            DiffReviewPanel(
                original: diff.original ?? "",
                proposed: diff.proposed,
                onAccept: { acceptDiff(messageId: messageId, diffIndex: diffIndex) },
                onReject: { rejectDiff(messageId: messageId, diffIndex: diffIndex) },
                isApplying: applyingDiffID == diffActionID(messageId: messageId, diffIndex: diffIndex)
            )
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
    }

    // MARK: - Input Area

    private var sendDisabled: Bool {
        !isConnected || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing || hasPendingDiffs
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(isFirstTurn ? "Enter instructions…" : "Follow up…", text: $inputText, axis: .vertical)
                .font(.body)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .disabled(isProcessing || !isConnected || hasPendingDiffs)
                .onSubmit {
                    if !sendDisabled { sendMessage() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))

            if isProcessing {
                Button {
                    agent?.cancelPrompt()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 36)
                        .frame(maxHeight: .infinity)
                        .background(Color.red.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Stop (⌘.)")
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 36)
                        .frame(maxHeight: .infinity)
                        .background(sendDisabled ? Color.accentColor.opacity(0.4) : Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (⌘↩)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    private var resizeHandle: some View {
        VStack(spacing: 0) {
            Color(.separatorColor)
                .frame(height: 1)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(isDragging ? 0.5 : 0.25))
                .frame(width: 36, height: 4)
                .padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    if dragStartHeight == nil {
                        dragStartHeight = panelHeight
                    }
                    let newHeight = (dragStartHeight ?? panelHeight) - value.translation.height
                    panelHeight = max(Self.minPanelHeight, min(Self.maxPanelHeight, newHeight))
                }
                .onEnded { _ in
                    isDragging = false
                    dragStartHeight = nil
                }
        )
    }

    private var connectionButton: some View {
        Button {
            if isConnected || isConnecting {
                forceDisconnect()
            } else {
                connect()
            }
        } label: {
            Group {
                if isConnecting {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "link")
                        .foregroundStyle(isConnected ? .green : .red)
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(isConnected ? "Disconnect" : isConnecting ? "Cancel connection" : "Connect to \(selectedAgent?.displayName ?? "agent")")
        .disabled(selectedAgentId == nil)
    }

    private var closeButton: some View {
        Button {
            forceDisconnect()
            isVisible = false
        } label: {
            Image(systemName: "xmark")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var debugLogButton: some View {
        if debugLoggingEnabled {
            Button {
                showingDebugLogs = true
            } label: {
                Image(systemName: "ladybug")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("View Agent Logs")
            .popover(isPresented: $showingDebugLogs) {
                AgentLogViewer()
                    .frame(width: 600, height: 400)
            }
        }
    }

    // MARK: - Actions

    private func connect() {
        guard let agentId = selectedAgent, !isConnected, !isConnecting else { return }
        let client = AgentFactory.make(for: agentId)
        agent = client  // agent's @Observable state drives the UI from this point
        let systemPrompt = TemplateManager.shared.systemPrompt(
            for: selectedTemplateType,
            skillName: skillName,
            skillDescription: skillDescription,
            filePath: filePath,
            frontmatter: frontmatter
        )
        client.startConnect(workingDirectory: workingDirectory, systemPrompt: systemPrompt)
    }

    private func sendMessage() {
        guard let client = agent else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, text: text))

        let assistantId = UUID()

        Task {
            do {
                let fp = filePath
                // Use the editor binding — it's the ground truth the user sees.
                // readFile(at:) reads disk, which may be stale (auto-save debounce).
                let original = content
                client.primeDeferredContent(for: fp, content: original)
                // The agent owns prompt construction (system prompt + file content +
                // user request). We just hand it the raw user text.
                try await client.prompt(text)
                isFirstTurn = false

                let raw = client.responseText
                let processed = client.conversationalText(from: raw)
                let finalText = processed.isEmpty ? raw : processed
                agentLog.info("Compose: turn done — raw=\(raw.count) chars, thought=\(client.thoughtText.count) chars")

                messages.append(ChatMessage(id: assistantId, role: .assistant, text: finalText, thoughtText: client.thoughtText))
                await handleWrites(client: client, messageId: assistantId, filePath: fp, originalContent: original)
            } catch is CancellationError {
                client.clearPendingWrites()
                messages.append(ChatMessage(id: assistantId, role: .assistant, text: "Stopped."))
            } catch {
                client.clearPendingWrites()
                messages.append(ChatMessage(id: assistantId, role: .assistant, text: error.localizedDescription, isError: true))
            }
        }
    }

    /// Reads a file off the main actor (UTF-8 with UTF-16 fallback).
    private func readFile(at path: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            (try? String(contentsOfFile: path, encoding: .utf8))
                ?? (try? String(contentsOfFile: path, encoding: .utf16))
        }.value
    }

    /// Attaches diffs from pending writes or disk changes; logs text-only turns.
    private func handleWrites(client: any AgentSession, messageId: UUID, filePath: String, originalContent: String) async {
        let autoAccept = client.isBypassMode
        agentLog.info("Compose: handleWrites — filePath=\(filePath) originalContent.count=\(originalContent.count) autoAccept=\(autoAccept)")
        if !client.pendingWrites.isEmpty {
            agentLog.info("Compose: attaching \(client.pendingWrites.count) diff(s) from write_text_file")
            await attachDiffs(messageId: messageId, writes: client.pendingWrites, fallbackOriginal: originalContent, autoAccept: autoAccept)
            client.clearPendingWrites()
            return
        }
        client.clearPendingWrites()
        let newContent = await readFile(at: filePath) ?? originalContent
        if newContent != originalContent {
            await attachDiffs(
                messageId: messageId,
                writes: [
                    PendingWrite(
                        path: filePath,
                        content: newContent,
                        originalText: originalContent,
                        originalData: originalContent.data(using: .utf8),
                        existedBefore: true
                    )
                ],
                fallbackOriginal: originalContent,
                autoAccept: autoAccept
            )
        }
    }

    /// Converts pending writes into ChatDiff entries and attaches them to the message.
    /// Uses the pre-write snapshot captured by the agent transport; do not reread disk here because
    /// the agent may already have mutated the file.
    /// Resolves `path` through symlinks so that e.g. a `.cursor/rules/foo.md` symlink
    /// and its target `~/.aidevtools/rules/foo.md` compare as equal.
    private func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func attachDiffs(
        messageId: UUID,
        writes: [PendingWrite],
        fallbackOriginal: String,
        autoAccept: Bool = false
    ) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let resolvedFilePath = resolvedPath(filePath)
        agentLog.debug("Compose: attachDiffs — filePath=\(filePath) resolved=\(resolvedFilePath) fallback.count=\(fallbackOriginal.count)")
        var diffs: [ChatDiff] = []
        for write in writes {
            let writtenResolved = resolvedPath(write.path)
            let original: String?
            let originalData: Data?
            let existedBefore: Bool
            if write.path == filePath || writtenResolved == resolvedFilePath {
                // Current file: always use our own snapshot from turn start.
                // The agent's oldText can be empty or wrong; fallbackOriginal is ground truth.
                original = fallbackOriginal
                originalData = fallbackOriginal.data(using: .utf8)
                existedBefore = true
            } else if let embedded = write.originalText {
                original = embedded
                originalData = write.originalData
                existedBefore = write.existedBefore
            } else {
                original = write.originalText
                originalData = write.originalData
                existedBefore = write.existedBefore
            }
            agentLog.debug("Compose: diff \(write.path) original=\(original?.count ?? -1) chars")
            // For direct-CLI agents the user has already approved this write via the
            // pre-flight permission sheet (which renders the diff). Mark it accepted so
            // the chat shows a record without prompting again. ACP-style writes (none today)
            // would still arrive as .pending.
            let initialStatus: DiffStatus = write.agentDidWrite ? .accepted : .pending
            diffs.append(
                ChatDiff(
                    path: write.path,
                    original: original,
                    originalData: originalData,
                    existedBefore: existedBefore,
                    proposed: write.content,
                    agentDidWrite: write.agentDidWrite,
                    status: initialStatus
                )
            )
        }
        messages[idx].diffs = diffs

        if autoAccept {
            // Bypass mode: auto-accept all diffs. Disk writes already happened in handleFileWriteRequest.
            let resolvedFilePath = resolvedPath(filePath)
            for i in messages[idx].diffs.indices {
                messages[idx].diffs[i].status = .accepted
                let diff = messages[idx].diffs[i]
                if resolvedPath(diff.path) == resolvedFilePath {
                    content = diff.proposed
                    onAccept()
                }
            }
        }
    }

    private func acceptDiff(messageId: UUID, diffIndex: Int) {
        guard let msgIdx = messages.firstIndex(where: { $0.id == messageId }),
              diffIndex < messages[msgIdx].diffs.count else { return }
        let diff = messages[msgIdx].diffs[diffIndex]
        if resolvedPath(diff.path) == resolvedPath(filePath) {
            messages[msgIdx].diffs[diffIndex].status = .accepted
            // Currently-open file: update editor binding, onAccept() persists to disk.
            // Direct-CLI agents already wrote to disk; skip re-persist to avoid a redundant write.
            content = diff.proposed
            if !diff.agentDidWrite {
                onAccept()
            }
        } else if diff.agentDidWrite {
            // Direct-CLI: file is already at proposed content on disk. Just mark accepted.
            messages[msgIdx].diffs[diffIndex].status = .accepted
        } else {
            let actionID = diffActionID(messageId: messageId, diffIndex: diffIndex)
            guard applyingDiffID != actionID else { return }
            applyingDiffID = actionID
            Task {
                do {
                    try await Self.persistAcceptedDiff(diff)
                    guard let updatedMsgIdx = messages.firstIndex(where: { $0.id == messageId }),
                          diffIndex < messages[updatedMsgIdx].diffs.count else {
                        applyingDiffID = nil
                        return
                    }
                    messages[updatedMsgIdx].diffs[diffIndex].status = .accepted
                } catch {
                    let fileName = URL(fileURLWithPath: diff.path).lastPathComponent
                    AppLogger.fileIO.error("Deferred diff apply failed for \(diff.path): \(error.localizedDescription)")
                    diffApplyError = DiffApplyError(
                        message: "Couldn't apply changes to \(fileName): \(error.localizedDescription)"
                    )
                }
                applyingDiffID = nil
            }
        }
    }

    private func rejectDiff(messageId: UUID, diffIndex: Int) {
        guard let msgIdx = messages.firstIndex(where: { $0.id == messageId }),
              diffIndex < messages[msgIdx].diffs.count else { return }
        let diff = messages[msgIdx].diffs[diffIndex]
        messages[msgIdx].diffs[diffIndex].status = .rejected

        // Direct-CLI agents (Claude, Codex) already wrote to disk by the time the user sees
        // the diff. Revert from the snapshot we captured pre-write.
        guard diff.agentDidWrite else { return }
        let resolvedDiffPath = resolvedPath(diff.path)
        let editorIsThisFile = resolvedDiffPath == resolvedPath(filePath)
        Task {
            do {
                try await Self.revertWrittenDiff(diff)
                if editorIsThisFile, let original = diff.original {
                    content = original
                }
            } catch {
                let fileName = URL(fileURLWithPath: diff.path).lastPathComponent
                AppLogger.fileIO.error("Revert failed for \(diff.path): \(error.localizedDescription)")
                diffApplyError = DiffApplyError(
                    message: "Couldn't revert \(fileName): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Restores a file to its pre-write state. If the file didn't exist before, removes it.
    nonisolated private static func revertWrittenDiff(_ diff: ChatDiff) async throws {
        try await Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: diff.path)
            if diff.existedBefore {
                if let originalData = diff.originalData {
                    try originalData.write(to: url, options: .atomic)
                } else if let original = diff.original {
                    try original.write(to: url, atomically: true, encoding: .utf8)
                }
            } else {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        }.value
    }

    private func diffActionID(messageId: UUID, diffIndex: Int) -> String {
        "\(messageId.uuidString)-\(diffIndex)"
    }

    nonisolated private static func persistAcceptedDiff(_ diff: ChatDiff) async throws {
        try await Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: diff.path)
            let parent = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
            }
            try diff.proposed.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }

    private func forceDisconnect() {
        let client = agent
        agent = nil
        isFirstTurn = true
        messages = []
        applyingDiffID = nil
        Task {
            await client?.disconnect()
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var content = "# Sample Skill\n\nThis is sample content."
    @Previewable @State var isVisible = true
    VStack {
        Text("Editor content above")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        ComposePanel(
            content: $content,
            isVisible: $isVisible,
            skillName: "sample-skill",
            filePath: "/tmp/sample-skill.md",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            templateType: .skill
        )
    }
    .frame(width: 600, height: 400)
}
