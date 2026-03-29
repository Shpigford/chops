import ACPModel
import ACPRegistry
import SwiftUI

/// Inline panel for composing/editing skill content with ACP
struct ComposePanel: View {
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
    @AppStorage("ACPSelectedAgentId") private var selectedAgentId: String?
    @State private var acpClient: BaseACPAgent?
    @State private var showingDebugLogs = false

    /// Completed conversation history. Never holds in-flight messages — the SDK drives live state.
    @State private var messages: [ChatMessage] = []
    /// True until the first successful prompt in this session.
    @State private var isFirstTurn = true

    @AppStorage("ACPDebugLogging") private var debugLoggingEnabled = false
    @State private var panelHeight: CGFloat = ComposeConstants.defaultPanelHeight
    @State private var isDragging = false
    @State private var dragStartHeight: CGFloat?

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

    private var configuredAgents: [RegistryAgent] { ACPConfiguration.shared.enabledAgents }
    private var selectedAgent: RegistryAgent? { configuredAgents.first { $0.id == selectedAgentId } }

    private var isConnected: Bool { acpClient?.isConnected ?? false }
    private var isConnecting: Bool { acpClient?.isConnecting ?? false }
    private var isProcessing: Bool { acpClient?.isProcessing ?? false }
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
                selectedAgentId = configuredAgents.first?.id
            }
        }
        .onDisappear {
            forceDisconnect()
        }
        .onChange(of: selectedAgentId) { _, _ in
            forceDisconnect()
        }
        .onChange(of: configuredAgents.map(\.id)) { _, newIds in
            if selectedAgentId == nil || !newIds.contains(selectedAgentId ?? "") {
                selectedAgentId = newIds.first
            }
        }
        .task { await ACPConfiguration.shared.loadRegistryIfNeeded() }
        .sheet(isPresented: Binding(
            get: { acpClient?.pendingPermissionRequest != nil },
            set: { if !$0 { acpClient?.respondToPermission(optionId: nil) } }
        )) {
            if let request = acpClient?.pendingPermissionRequest {
                permissionSheet(request: request)
            }
        }
    }

    @ViewBuilder
    private func permissionSheet(request: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Permission Required", systemImage: "hand.raised.fill")
                .font(.headline)
            Text(request.title)
                .foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(request.options, id: \.optionId) { option in
                    Button(option.name) {
                        acpClient?.respondToPermission(optionId: option.optionId)
                    }
                    .buttonStyle(.bordered)
                    .tint(permissionOptionTint(for: option.kind))
                }
            }
            Divider()
            Button("Cancel") {
                acpClient?.respondToPermission(optionId: nil)
            }
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 320, maxWidth: 440)
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
                    ForEach(configuredAgents) { agent in
                        Text(agent.name).tag(Optional(agent.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                if selectedAgentId != nil {
                    if isConnecting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Connecting…")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            closeButton
                .padding(12)
        }
    }

    private let configuration = ACPConfiguration.shared

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
                    if configuration.isLoadingRegistry {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Loading agents…").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(configuration.registryAgents) { agent in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(agent.name)
                                        .font(.callout.weight(.medium))
                                    Text(agent.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { configuration.isEnabled(agent.id) },
                                    set: { configuration.setEnabled(agent.id, $0) }
                                ))
                                .labelsHidden()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
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
        .task { await configuration.loadRegistryIfNeeded() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            // LEFT: Tool picker + connection + debug
            HStack(spacing: 8) {
                Picker("", selection: $selectedAgentId) {
                    Text("Select...").tag(nil as String?)
                    ForEach(configuredAgents) { agent in
                        Text(agent.name).tag(Optional(agent.id))
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                connectionButton
                debugLogButton
            }

            Spacer()

            // Error indicator — connection errors reported by the agent.
            if let error = acpClient?.lastError {
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

            // RIGHT: config options (when connected) + close
            HStack(spacing: 8) {
                inlineConfigOptions
                closeButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Config Options Bar

    /// Inline config option pickers shown in the top bar when connected.
    @ViewBuilder
    private var inlineConfigOptions: some View {
        let options = acpClient?.sessionConfigOptions ?? []
        if isConnected && !options.isEmpty {
            ForEach(options, id: \.id) { option in
                if case .select(let select) = option.kind {
                    configOptionPicker(option: option, select: select)
                }
            }
        }
    }

    @ViewBuilder
    private func configOptionPicker(option: SessionConfigOption, select: SessionConfigSelect) -> some View {
        let flatOptions: [SessionConfigSelectOption] = {
            switch select.options {
            case .ungrouped(let opts): return opts
            case .grouped(let groups): return groups.flatMap(\.options)
            }
        }()
        Picker(option.name, selection: Binding(
            get: { select.currentValue },
            set: { newValue in
                Task { try? await acpClient?.setConfigOption(id: option.id, value: newValue) }
            }
        )) {
            ForEach(flatOptions, id: \.value) { opt in
                Text(opt.name.replacingOccurrences(of: " (recommended)", with: "")).tag(opt.value)
            }
        }
        .fixedSize()
        .help(option.description ?? option.name)
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
                .onChange(of: acpClient?.currentActivity) { _, _ in
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
        let thoughtText = acpClient?.thoughtText ?? ""
        let responseText = acpClient?.responseText ?? ""
        let displayText = acpClient?.conversationalText(from: responseText) ?? responseText
        let activity = acpClient?.currentActivity

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
                } else if let activity {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(activity).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Working…").foregroundStyle(.secondary)
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
                onReject: { rejectDiff(messageId: messageId, diffIndex: diffIndex) }
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
                    acpClient?.cancelPrompt()
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
        .help(isConnected ? "Disconnect" : isConnecting ? "Cancel connection" : "Connect to \(selectedAgent?.name ?? "agent")")
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
            .help("View ACP Logs")
            .popover(isPresented: $showingDebugLogs) {
                ACPLogViewer()
                    .frame(width: 600, height: 400)
            }
        }
    }

    // MARK: - Actions

    private func connect() {
        guard let agent = selectedAgent, !isConnected, !isConnecting else { return }
        let client = ACPAgentFactory.make(for: agent.id)
        acpClient = client  // agent's @Observable state drives the UI from this point
        let systemPrompt = TemplateManager.shared.systemPrompt(
            for: selectedTemplateType,
            skillName: skillName,
            skillDescription: skillDescription,
            filePath: filePath,
            frontmatter: frontmatter
        )
        client.startConnect(agent: agent, workingDirectory: workingDirectory, systemPrompt: systemPrompt)
    }

    private func sendMessage() {
        guard let client = acpClient else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, text: text))

        let assistantId = UUID()

        Task {
            do {
                let fp = filePath
                let original: String? = await readFile(at: fp)
                guard let original else {
                    messages.append(ChatMessage(id: assistantId, role: .assistant, text: "Cannot read file: \(filePath)", isError: true))
                    return
                }
                let prompt = buildPrompt(text: text, originalContent: original)
                try await client.prompt(prompt)
                isFirstTurn = false

                let raw = client.responseText
                let processed = client.conversationalText(from: raw)
                let finalText = processed.isEmpty ? raw : processed
                acpLog.info("Compose: turn done — raw=\(raw.count) chars, thought=\(client.thoughtText.count) chars")

                messages.append(ChatMessage(id: assistantId, role: .assistant, text: finalText, thoughtText: client.thoughtText))
                await handleWrites(client: client, messageId: assistantId, filePath: fp, originalContent: original)
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

    /// Expands the template on the first turn; returns plain text on subsequent turns.
    private func buildPrompt(text: String, originalContent: String) -> String {
        guard isFirstTurn, let template = TemplateManager.shared.template(for: selectedTemplateType) else {
            return text
        }
        return template.content
            .replacingOccurrences(of: "{{file_content}}", with: originalContent.isEmpty ? "(empty)" : originalContent)
            .replacingOccurrences(of: "{{user_instructions}}", with: text)
    }

    /// Attaches diffs from pending writes or disk changes; logs text-only turns.
    private func handleWrites(client: BaseACPAgent, messageId: UUID, filePath: String, originalContent: String) async {
        acpLog.info("Compose: handleWrites — filePath=\(filePath) originalContent.count=\(originalContent.count)")
        if !client.pendingWrites.isEmpty {
            acpLog.info("Compose: attaching \(client.pendingWrites.count) diff(s) from write_text_file")
            await attachDiffs(messageId: messageId, writes: client.pendingWrites, fallbackOriginal: originalContent)
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
                fallbackOriginal: originalContent
            )
        }
    }

    /// Converts pending writes into ChatDiff entries and attaches them to the message.
    /// Uses the pre-write snapshot captured by the ACP layer; do not reread disk here because
    /// the agent may already have mutated the file.
    /// Resolves `path` through symlinks so that e.g. a `.cursor/rules/foo.md` symlink
    /// and its target `~/.aidevtools/rules/foo.md` compare as equal.
    private func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func attachDiffs(
        messageId: UUID,
        writes: [PendingWrite],
        fallbackOriginal: String
    ) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let resolvedFilePath = resolvedPath(filePath)
        acpLog.debug("Compose: attachDiffs — filePath=\(filePath) resolved=\(resolvedFilePath) fallback.count=\(fallbackOriginal.count)")
        var diffs: [ChatDiff] = []
        for write in writes {
            let writtenResolved = resolvedPath(write.path)
            let original: String?
            let originalData: Data?
            let existedBefore: Bool
            if let embedded = write.originalText {
                // Agent supplied the pre-edit content (e.g. DiffContent.oldText) — use it directly.
                original = embedded
                originalData = write.originalData
                existedBefore = write.existedBefore
            } else if write.path == filePath || writtenResolved == resolvedFilePath {
                // Path matches (accounting for symlinks) — use the in-memory content from before the turn.
                original = fallbackOriginal
                originalData = fallbackOriginal.data(using: .utf8)
                existedBefore = true
            } else {
                original = write.originalText
                originalData = write.originalData
                existedBefore = write.existedBefore
            }
            acpLog.debug("Compose: diff \(write.path) original=\(original?.count ?? -1) chars")
            diffs.append(
                ChatDiff(
                    path: write.path,
                    original: original,
                    originalData: originalData,
                    existedBefore: existedBefore,
                    proposed: write.content
                )
            )
        }
        messages[idx].diffs = diffs
    }

    private func pendingDiffs() -> [ChatDiff] {
        messages.flatMap(\.diffs).filter { $0.status == .pending }
    }

    nonisolated private static func revertDiffOnDisk(_ diff: ChatDiff) {
        let url = URL(fileURLWithPath: diff.path)
        if diff.existedBefore {
            do {
                if let originalData = diff.originalData {
                    try originalData.write(to: url)
                } else if let original = diff.original {
                    try original.write(to: url, atomically: true, encoding: .utf8)
                } else {
                    acpLog.error("Reject failed: missing original snapshot for \(diff.path)")
                }
            } catch {
                acpLog.error("Reject failed writing \(diff.path): \(error.localizedDescription)")
            }
        } else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                acpLog.error("Reject failed removing \(diff.path): \(error.localizedDescription)")
            }
        }
    }

    private func acceptDiff(messageId: UUID, diffIndex: Int) {
        guard let msgIdx = messages.firstIndex(where: { $0.id == messageId }),
              diffIndex < messages[msgIdx].diffs.count else { return }
        let diff = messages[msgIdx].diffs[diffIndex]
        messages[msgIdx].diffs[diffIndex].status = .accepted
        if resolvedPath(diff.path) == resolvedPath(filePath) {
            content = diff.proposed
            onAccept()
        }
    }

    private func rejectDiff(messageId: UUID, diffIndex: Int) {
        guard let msgIdx = messages.firstIndex(where: { $0.id == messageId }),
              diffIndex < messages[msgIdx].diffs.count else { return }
        let diff = messages[msgIdx].diffs[diffIndex]
        messages[msgIdx].diffs[diffIndex].status = .rejected
        Task.detached(priority: .userInitiated) {
            Self.revertDiffOnDisk(diff)
        }
    }

    private func forceDisconnect() {
        let client = acpClient
        let pendingDiffs = pendingDiffs()
        acpClient = nil
        isFirstTurn = true
        messages = []
        Task {
            if !pendingDiffs.isEmpty {
                await Task.detached(priority: .userInitiated) {
                    pendingDiffs.forEach(Self.revertDiffOnDisk)
                }.value
            }
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
