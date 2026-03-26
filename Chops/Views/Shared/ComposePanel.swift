import SwiftUI

// MARK: - Chat Model

enum ChatRole { case user, assistant }

enum DiffStatus { case pending, accepted, rejected }

struct ChatDiff {
    let original: String
    let proposed: String
    var status: DiffStatus = .pending
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var text: String
    var isStreaming: Bool
    var isError: Bool
    var diff: ChatDiff?

    init(id: UUID = UUID(), role: ChatRole, text: String, isStreaming: Bool = false, isError: Bool = false, diff: ChatDiff? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.isError = isError
        self.diff = diff
    }
}

/// Connection state for ACP
enum ComposeConnectionState {
    case disconnected
    case connecting
    case connected
}

/// Inline panel for composing/editing skill content with ACP
struct ComposePanel: View {
    @Binding var content: String
    @Binding var isVisible: Bool
    let skillName: String
    /// Absolute path of the file being edited — used to read source-of-truth from disk.
    let filePath: String
    let workingDirectory: URL

    @State private var selectedTemplateType: WizardTemplateType
    @State private var inputText = ""
    @State private var selectedTool: ToolSource?
    @State private var connectionState: ComposeConnectionState = .disconnected
    @State private var compositionError: String?
    @State private var acpClient: ACPClient?
    @State private var connectTask: Task<Void, Never>?
    @State private var showingDebugLogs = false

    @State private var messages: [ChatMessage] = []
    @State private var streamingMessageId: UUID?
    /// True until the first successful prompt in this session.
    @State private var isFirstTurn = true

    @State private var panelHeight: CGFloat = 300
    @State private var isDragging = false
    @State private var dragStartHeight: CGFloat?

    private static let minPanelHeight: CGFloat = 160
    private static let maxPanelHeight: CGFloat = 700

    init(
        content: Binding<String>,
        isVisible: Binding<Bool>,
        skillName: String,
        filePath: String,
        workingDirectory: URL,
        templateType: WizardTemplateType
    ) {
        self._content = content
        self._isVisible = isVisible
        self.skillName = skillName
        self.filePath = filePath
        self.workingDirectory = workingDirectory
        self._selectedTemplateType = State(initialValue: templateType)
    }

    private var configuredTools: [ToolSource] {
        ACPConfiguration.supportedTools.filter {
            ACPConfiguration.shared.config(for: $0)?.isValid ?? false
        }
    }

    private var isConnected: Bool { connectionState == .connected }
    private var isComposing: Bool { streamingMessageId != nil }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle

            if configuredTools.isEmpty {
                noToolsConfiguredView
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
            if selectedTool == nil {
                selectedTool = configuredTools.first
            }
        }
        .onDisappear {
            forceDisconnect()
        }
        .onChange(of: selectedTool) { _, _ in
            forceDisconnect()
        }
    }

    // MARK: - Views

    private var noToolsConfiguredView: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("No ACP tools configured.")
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.link)
            Spacer()
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            // LEFT: Tool picker + connection + debug
            HStack(spacing: 8) {
                Picker("", selection: $selectedTool) {
                    Text("Select...").tag(nil as ToolSource?)
                    ForEach(configuredTools) { tool in
                        Text(tool.displayName).tag(Optional(tool))
                    }
                }
                .labelsHidden()
                .frame(width: 100)

                connectionButton
                debugLogButton
            }

            Spacer()

            // Error indicator
            if let error = compositionError {
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

            // RIGHT: Template picker + close
            // Always visible so the selection is clear; disabled after first turn.
            HStack(spacing: 12) {
                Picker("", selection: $selectedTemplateType) {
                    ForEach(WizardTemplateType.allCases) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .disabled(!isFirstTurn)
                .help(isFirstTurn ? "Template for this session" : "Reconnect to change template")
                closeButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Chat Area

    /// Messages that should appear in the chat. Hides finalized assistant messages
    /// with no text and no diff — these are thinking-only turns with no user-visible output.
    private var visibleMessages: [ChatMessage] {
        messages.filter { msg in
            guard msg.role == .assistant, !msg.isStreaming, msg.text.isEmpty,
                  !msg.isError, msg.diff == nil else { return true }
            return false
        }
    }

    private var chatArea: some View {
        GeometryReader { geo in
            let bubbleWidth = max(200, floor(geo.size.width * 0.72))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            if isConnected {
                                connectedPlaceholder
                            } else {
                                disconnectedPlaceholder
                            }
                        }
                        ForEach(visibleMessages) { message in
                            chatRow(message: message, bubbleWidth: bubbleWidth)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                }
                .background(Color(.textBackgroundColor).opacity(0.3))
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: streamingMessageId) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var disconnectedPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Connect an agent to start composing")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var connectedPlaceholder: some View {
        Text("Session ready. Send your first instruction.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

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
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: bubbleWidth, alignment: .trailing)
                }
            case .assistant:
                assistantCard(message: message)
                    .frame(maxWidth: bubbleWidth, alignment: .leading)
            }
            if let diff = message.diff {
                diffCard(messageId: message.id, diff: diff)
            }
        }
    }

    @ViewBuilder
    private func assistantCard(message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 4) {
                if message.isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Error")
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                    Text("Agent")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()
                .padding(.horizontal, 8)

            // Body
            if message.isStreaming && message.text.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Thinking…").foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else if message.isError {
                Text(message.text)
                    .font(.body.italic())
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                markdownText(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Use a primary-relative tint so the card is visibly distinct from the window
        // background in both light and dark mode (controlBackgroundColor is too similar).
        .background(message.isError ? Color.orange.opacity(0.08) : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(message.isError ? Color.orange.opacity(0.35) : Color.secondary.opacity(0.2))
        )
    }

    /// Renders text with inline markdown. Falls back to plain text if parsing fails.
    private func markdownText(_ raw: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: raw, options: options) {
            return Text(attributed)
        }
        return Text(raw)
    }

    @ViewBuilder
    private func diffCard(messageId: UUID, diff: ChatDiff) -> some View {
        switch diff.status {
        case .accepted:
            HStack(spacing: 6) {
                Label("Changes accepted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("· Press ⌘S to save")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
        case .rejected:
            Label("Changes rejected", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        case .pending:
            DiffReviewPanel(
                original: diff.original,
                proposed: diff.proposed,
                onAccept: { acceptDiff(messageId: messageId) },
                onReject: { rejectDiff(messageId: messageId) }
            )
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text(isFirstTurn ? "Enter instructions…" : "Follow up…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $inputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 36, maxHeight: 80)
                    .disabled(isComposing || !isConnected)
            }
            .padding(.horizontal, 4)
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

            Button {
                sendMessage()
            } label: {
                Group {
                    if isComposing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isConnected || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isComposing)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    private var resizeHandle: some View {
        ZStack {
            Color(.separatorColor)
                .frame(height: 1)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(isDragging ? 0.5 : 0.25))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 10)
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
            if isConnected {
                forceDisconnect()
            } else if connectionState == .disconnected {
                connect()
            }
        } label: {
            Group {
                switch connectionState {
                case .disconnected:
                    Image(systemName: "link")
                        .foregroundStyle(.red)
                case .connecting:
                    ProgressView()
                        .controlSize(.mini)
                case .connected:
                    Image(systemName: "link")
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(connectionState == .connected ? "Disconnect" : "Connect to \(selectedTool?.displayName ?? "agent")")
        .disabled(selectedTool == nil)
    }

    private var closeButton: some View {
        Button {
            forceDisconnect()
            isVisible = false
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var debugLogButton: some View {
        Button {
            showingDebugLogs = true
        } label: {
            Image(systemName: "ladybug")
                .foregroundStyle(acpLog.debugEnabled ? .orange : .secondary)
        }
        .buttonStyle(.plain)
        .help("View ACP Logs")
        .popover(isPresented: $showingDebugLogs) {
            ACPLogViewer()
                .frame(width: 600, height: 400)
        }
    }

    // MARK: - Actions

    private func connect() {
        guard let tool = selectedTool, connectionState == .disconnected else { return }

        connectionState = .connecting
        compositionError = nil

        connectTask = Task { @MainActor in
            do {
                let client = ACPClient()
                try await client.connect(tool: tool, workingDirectory: workingDirectory)
                _ = try await client.createSession(cwd: workingDirectory)
                acpClient = client
                connectionState = .connected
            } catch {
                compositionError = error.localizedDescription
                connectionState = .disconnected
                acpClient = nil
            }
        }
    }

    private func forceDisconnect() {
        connectTask?.cancel()
        connectTask = nil

        let client = acpClient
        acpClient = nil
        connectionState = .disconnected
        streamingMessageId = nil
        isFirstTurn = true
        messages = []  // Clear chat history — new session starts fresh.

        if let client {
            Task { await client.disconnect() }
        }
    }

    private func sendMessage() {
        guard let client = acpClient else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        compositionError = nil

        // Append the user bubble immediately
        messages.append(ChatMessage(role: .user, text: text))

        // Append a streaming placeholder for the assistant
        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, text: "", isStreaming: true))
        streamingMessageId = assistantId

        Task { @MainActor in
            do {
                // Read the file off the main actor — synchronous I/O blocks the main thread.
                // Attempt UTF-8 first; fall back to UTF-16 for files saved by older macOS apps.
                // Fail fast if the file cannot be read — feeding the template with wrong content
                // produces a meaningless diff and risks data loss.
                let fp = filePath
                let originalDiskContent: String? = await Task.detached(priority: .userInitiated) {
                    (try? String(contentsOfFile: fp, encoding: .utf8))
                        ?? (try? String(contentsOfFile: fp, encoding: .utf16))
                }.value
                guard let originalDiskContent else {
                    finalizeMessage(id: assistantId, text: "Cannot read file: \(filePath)", isError: true)
                    streamingMessageId = nil
                    return
                }

                // First turn: expand the full template. Subsequent turns: send plain text so
                // the agent uses its existing session context and doesn't re-process the file.
                let prompt: String
                if isFirstTurn, let template = TemplateManager.shared.template(for: selectedTemplateType) {
                    prompt = template.content
                        .replacingOccurrences(of: "{{file_content}}", with: originalDiskContent.isEmpty ? "(empty)" : originalDiskContent)
                        .replacingOccurrences(of: "{{user_instructions}}", with: text)
                } else {
                    prompt = text
                }

                try await client.prompt(prompt)
                isFirstTurn = false

                // Adaptive silence timeout — resets on every streaming event, tool call, or thought.
                // 60 s gives slow agents (long file reads, multi-step plans) room to breathe.
                // Hard cap at 15 min is a last-resort backstop.
                let silenceTimeout: TimeInterval = 60
                let hardCap = Date().addingTimeInterval(900)
                var timedOut = false
                while client.state == .prompting && Date() < hardCap {
                    try await Task.sleep(for: .milliseconds(200))
                    updateStreamingMessage(id: assistantId, text: client.responseText)
                    if Date().timeIntervalSince(client.lastActivityDate) > silenceTimeout {
                        acpLog.info("Compose: silence timeout — treating turn as complete")
                        timedOut = true
                        break
                    }
                }

                // If we timed out with no response at all, surface it as an error card.
                let responseText = client.responseText
                if timedOut && responseText.isEmpty {
                    finalizeMessage(id: assistantId, text: "No response from agent (silence timeout).", isError: true)
                } else {
                    finalizeMessage(id: assistantId, text: responseText)
                }
                streamingMessageId = nil

                // Priority 1: agent used fs/write_text_file
                if let write = client.pendingWrite {
                    acpLog.info("Compose: attaching diff from write_text_file interception")
                    attachDiff(messageId: assistantId, original: originalDiskContent, proposed: write.content)
                    client.clearPendingWrite()
                    return
                }
                client.clearPendingWrite()

                // Priority 2: agent used a native file-editing tool (e.g. str-replace-editor)
                let newDiskContent = await Task.detached(priority: .userInitiated) {
                    (try? String(contentsOfFile: fp, encoding: .utf8))
                        ?? (try? String(contentsOfFile: fp, encoding: .utf16))
                        ?? originalDiskContent
                }.value
                if newDiskContent != originalDiskContent {
                    acpLog.info("Compose: agent edited file on disk — attaching diff")
                    attachDiff(messageId: assistantId, original: originalDiskContent, proposed: newDiskContent)
                    return
                }

                // Priority 3: text-only reply — no file change
                if !client.responseText.isEmpty {
                    acpLog.info("Compose: agent responded with text only (no file written)")
                }
            } catch {
                // Ensure we always clean up, including any intercepted write from before the throw.
                client.clearPendingWrite()
                finalizeMessage(id: assistantId, text: error.localizedDescription, isError: true)
                streamingMessageId = nil
            }
        }
    }

    private func updateStreamingMessage(id: UUID, text: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text = text
    }

    private func finalizeMessage(id: UUID, text: String, isError: Bool = false) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text = text
        messages[idx].isStreaming = false
        messages[idx].isError = isError
    }

    private func attachDiff(messageId: UUID, original: String, proposed: String) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].diff = ChatDiff(original: original, proposed: proposed)
    }

    private func acceptDiff(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              let diff = messages[idx].diff else { return }
        // Update the editor binding immediately so the user sees the change.
        content = diff.proposed
        messages[idx].diff?.status = .accepted
        // Write atomically to disk. On failure, roll back the binding and show an error.
        do {
            try diff.proposed.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            acpLog.error("acceptDiff: disk write failed — \(error.localizedDescription)")
            content = diff.original
            messages[idx].diff?.status = .rejected
            compositionError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func rejectDiff(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].diff?.status = .rejected
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
