import ACP
import ACPModel
import ACPRegistry
import Foundation

// MARK: - Permission Request

struct PermissionRequest: Identifiable, @unchecked Sendable {
    let id: UUID = UUID()
    let title: String
    let options: [PermissionOption]
    let continuation: CheckedContinuation<RequestPermissionResponse, Error>
}

struct PendingWrite: Sendable {
    let path: String
    let content: String
    let originalText: String?
    let originalData: Data?
    let existedBefore: Bool
}

/// Base class for ACP agent interaction. Owns an `ACP.Client` actor and conforms to `ClientDelegate`.
/// Subclass to override vendor-specific hooks: additionalFlags, postProcess, conversationalText,
/// resolvePermission, and the onXxx stream callbacks.
@Observable
@MainActor
open class BaseACPAgent: ClientDelegate {

    // MARK: - Observable State

    var responseText: String = ""
    var thoughtText: String = ""
    var currentActivity: String?
    var pendingWrites: [PendingWrite] = []
    private(set) var sessionConfigOptions: [SessionConfigOption] = []
    private(set) var pendingPermissionRequest: PermissionRequest?
    private(set) var isConnected: Bool = false
    private(set) var isConnecting: Bool = false
    private(set) var isProcessing: Bool = false
    private(set) var lastError: String?
    private(set) var currentAgentId: String?

    // MARK: - Private Handles

    private var acpClient: ACP.Client?
    private var sessionId: SessionId?
    private var connectTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var pendingSystemPrompt: String?

    // MARK: - Connect / Disconnect

    /// Starts connecting non-blocking. Observe isConnecting / isConnected / lastError for state.
    func startConnect(agent: RegistryAgent, workingDirectory: URL, systemPrompt: String?) {
        connectTask?.cancel()
        lastError = nil
        connectTask = Task {
            defer { connectTask = nil }
            do {
                try await connect(agent: agent, workingDirectory: workingDirectory, systemPrompt: systemPrompt)
            } catch is CancellationError {
                // user-initiated — no error shown
            } catch {
                acpLog.error("Connection failed: \(error.localizedDescription)")
                lastError = error.localizedDescription
            }
        }
    }

    private func connect(agent: RegistryAgent, workingDirectory: URL, systemPrompt: String?) async throws {
        guard ACPConfiguration.shared.isEnabled(agent.id) else {
            throw ACPClientError.agentNotConfigured(agent.id)
        }
        currentAgentId = agent.id
        acpLog.debug("Resolving agent: \(agent.id) v\(agent.version)")
        let installed = try await ACPConfiguration.shared.resolve(agent)
        acpLog.debug("Resolved: \(installed.executablePath) args=[\(installed.arguments.joined(separator: " "))]")
        try await attemptConnect(installed: installed, workingDirectory: workingDirectory, systemPrompt: systemPrompt)
    }

    private func attemptConnect(installed: InstalledAgent, workingDirectory: URL, systemPrompt: String?) async throws {
        pendingSystemPrompt = systemPrompt
        isConnecting = true
        defer { isConnecting = false }

        let arguments = installed.arguments + additionalFlags()
        let environment = installed.environment.isEmpty ? nil : installed.environment

        let execPath = await resolveExecutable(installed.executablePath)
        acpLog.debug("launch: \(execPath) | args: \(arguments.joined(separator: " "))")

        let client = ACP.Client()
        await client.setDelegate(self)

        // SDK's ProcessManager loads the full login-shell environment internally.
        // Custom env from the registry (e.g. API keys) is merged on top by the SDK.
        try await client.launch(
            agentPath: execPath,
            arguments: arguments,
            workingDirectory: workingDirectory.path,
            environment: environment
        )
        guard !Task.isCancelled else { await client.terminate(); return }

        let initResp = try await client.initialize(
            capabilities: ClientCapabilities(
                fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
                terminal: false
            ),
            clientInfo: ClientInfo(name: "Chops", version: "1.0")
        )
        guard !Task.isCancelled else { await client.terminate(); return }
        acpLog.debug("Connected: \(initResp.agentInfo?.name ?? "?") (protocol v\(initResp.protocolVersion))")

        let cwd = sessionCwd(for: workingDirectory)
        let sessionResp = try await client.newSession(workingDirectory: cwd.path)
        guard !Task.isCancelled else { await client.terminate(); return }
        sessionId = sessionResp.sessionId
        sessionConfigOptions = sessionResp.configOptions ?? []
        acpLog.debug("Session created: \(sessionResp.sessionId) (\(sessionConfigOptions.count) config options)")

        acpClient = client
        isConnected = true
        startNotificationMonitor(client: client)
    }

    func disconnect() async {
        connectTask?.cancel()
        connectTask = nil
        notificationTask?.cancel()
        notificationTask = nil
        // Resume any parked permission continuation before tearing down —
        // CheckedContinuation will crash if it is never resumed.
        if let req = pendingPermissionRequest {
            pendingPermissionRequest = nil
            req.continuation.resume(returning: RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true)))
        }
        let client = acpClient
        acpClient = nil
        sessionId = nil
        isConnected = false
        currentAgentId = nil
        lastError = nil
        sessionConfigOptions = []
        pendingSystemPrompt = nil
        await client?.terminate()
        acpLog.debug("Disconnected")
    }

    // MARK: - Notification Monitor

    private func startNotificationMonitor(client: ACP.Client) {
        notificationTask?.cancel()
        notificationTask = Task.detached { [weak self] in
            let stream = await client.notifications
            for await notification in stream {
                guard !Task.isCancelled else { break }
                guard notification.method == "session/update" else { continue }
                await self?.handleRawNotification(notification)
            }
            // Stream ended — agent process likely exited
            await self?.onAgentDisconnected()
        }
    }

    private func onAgentDisconnected() {
        if isConnected {
            isConnected = false
            // Resume any parked permission continuation so it doesn't leak.
            if let req = pendingPermissionRequest {
                pendingPermissionRequest = nil
                req.continuation.resume(returning: RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true)))
            }
            acpLog.debug("Agent process ended")
        }
    }

    private func handleRawNotification(_ notification: JSONRPCNotification) {
        guard let params = notification.params else { return }
        do {
            let data = try JSONEncoder().encode(params)
            struct SessionUpdateParams: Codable {
                let sessionId: String
                let update: SessionUpdate
            }
            let decoded = try JSONDecoder().decode(SessionUpdateParams.self, from: data)
            handleUpdate(decoded.update)
        } catch {
            acpLog.debug("Failed to decode session update: \(error)")
        }
    }

    // MARK: - Session

    func setConfigOption(id: SessionConfigId, value: SessionConfigValueId) async throws {
        guard let client = acpClient, let sid = sessionId else { return }
        let resp = try await client.setConfigOption(sessionId: sid, configId: id, value: value)
        sessionConfigOptions = resp.configOptions
    }

    // MARK: - Prompt

    func prompt(_ text: String) async throws {
        guard let client = acpClient, let sid = sessionId else { throw ACPClientError.noSession }
        responseText = ""; thoughtText = ""; pendingWrites = []; currentActivity = nil
        isProcessing = true
        defer { isProcessing = false }

        // Prepend system prompt context to the first message of the session.
        let fullText: String
        if let sp = pendingSystemPrompt {
            pendingSystemPrompt = nil
            fullText = sp.isEmpty ? text : "\(sp)\n\n---\n\n\(text)"
        } else {
            fullText = text
        }

        let resp = try await client.sendPrompt(
            sessionId: sid,
            content: [.text(TextContent(text: fullText))]
        )
        currentActivity = nil
        acpLog.debug("Prompt done: \(resp.stopReason)")
    }

    func clearPendingWrites() { pendingWrites = [] }

    /// Sends a session/cancel notification to the agent to interrupt the current turn.
    func cancelPrompt() {
        guard let client = acpClient, let sid = sessionId else { return }
        Task {
            do {
                try await client.cancelSession(sessionId: sid)
            } catch {
                acpLog.error("Cancel failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Permission

    func parkPermissionRequest(title: String, options: [PermissionOption]) async throws -> RequestPermissionResponse {
        try await withCheckedThrowingContinuation { cont in
            pendingPermissionRequest = PermissionRequest(title: title, options: options, continuation: cont)
        }
    }

    func respondToPermission(optionId: String?) {
        guard let req = pendingPermissionRequest else { return }
        pendingPermissionRequest = nil
        if let id = optionId {
            req.continuation.resume(returning: RequestPermissionResponse(outcome: PermissionOutcome(optionId: id)))
        } else {
            req.continuation.resume(returning: RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true)))
        }
    }

    // MARK: - ClientDelegate

    public func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        acpLog.debug("readTextFile: \(path)")
        let content = try await Task.detached { try String(contentsOfFile: path, encoding: .utf8) }.value
        return ReadTextFileResponse(content: content)
    }

    public func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        acpLog.debug("Write via ACP: \(path)")
        // Read original before writing so reject can revert.
        // Skip if a diff block already captured this path (e.g. ClaudeACPAgent.captureDiffs).
        // Resolve symlinks on both sides so that e.g. a symlink path and its target compare equal.
        let resolvedIncoming = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let alreadyCaptured = pendingWrites.contains {
            URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == resolvedIncoming
        }
        if !alreadyCaptured {
            let snapshot = await Task.detached {
                let existedBefore = FileManager.default.fileExists(atPath: path)
                let originalData: Data?
                if existedBefore {
                    do {
                        originalData = try Data(contentsOf: URL(fileURLWithPath: path))
                    } catch {
                        acpLog.error("Failed to read original for diff revert (\(path)): \(error.localizedDescription)")
                        originalData = nil
                    }
                } else {
                    originalData = nil
                }
                return (existedBefore, originalData, Self.decodeText(from: originalData))
            }.value
            pendingWrites.append(
                PendingWrite(
                    path: path,
                    content: content,
                    originalText: snapshot.2,
                    originalData: snapshot.1,
                    existedBefore: snapshot.0
                )
            )
        }
        // Write to disk — agent expects the file to be persisted.
        try await Task.detached {
            let url = URL(fileURLWithPath: path)
            let parent = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
        return WriteTextFileResponse()
    }

    public func handleTerminalCreate(command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?) async throws -> CreateTerminalResponse {
        throw ACPClientError.terminalNotSupported
    }

    public func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        throw ACPClientError.terminalNotSupported
    }

    public func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        throw ACPClientError.terminalNotSupported
    }

    public func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        throw ACPClientError.terminalNotSupported
    }

    public func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        throw ACPClientError.terminalNotSupported
    }

    public func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        let title = request.message ?? "Permission Required"
        let options = request.options ?? []
        acpLog.debug("Permission: \(title)")
        return try await resolvePermission(title: title, options: options)
    }

    // MARK: - Session Update Dispatch

    func handleUpdate(_ update: SessionUpdate) {
        switch update {
        case .agentMessageChunk(let c):   onMessageChunk(c)
        case .agentThoughtChunk(let c):   onThoughtChunk(c)
        case .toolCall(let t):            onToolCall(t)
        case .toolCallUpdate(let d):      onToolCallUpdate(d)
        case .configOptionUpdate(let u):  sessionConfigOptions = u
        case .sessionInfoUpdate(let i):   if let t = i.title { acpLog.debug("Session: \(t)") }
        default:                          break
        }
    }

    // MARK: - Vendor Hooks (override in subclass)

    func onThoughtChunk(_ content: ContentBlock) {
        if case .text(let t) = content { currentActivity = String(t.text.prefix(80)) }
    }

    func onMessageChunk(_ content: ContentBlock) {
        if case .text(let t) = content { responseText += t.text }
    }

    func onToolCall(_ update: ToolCallUpdate) {
        currentActivity = (update.status == .completed || update.status == .failed) ? nil : update.title
    }

    func onToolCallUpdate(_ update: ToolCallUpdateDetails) {
        if let status = update.status, status == .completed || status == .failed {
            currentActivity = nil
        } else if let title = update.title {
            currentActivity = title
        }
    }

    func additionalFlags() -> [String] { [] }
    func sessionCwd(for workingDirectory: URL) -> URL { workingDirectory }
    func postProcess(_ text: String) -> String { text }
    func conversationalText(from text: String) -> String { postProcess(text) }

    func resolvePermission(title: String, options: [PermissionOption]) async throws -> RequestPermissionResponse {
        try await parkPermissionRequest(title: title, options: options)
    }

    // MARK: - Helpers

    /// Resolves a bare executable name (e.g. "npx") to its absolute path via the user's shell PATH.
    /// Returns the original name unchanged if it is already absolute or not found in PATH.
    private func resolveExecutable(_ name: String) async -> String {
        guard !name.hasPrefix("/") else { return name }
        let env = await ShellEnvironment.loadUserShellEnvironmentAsync()
        let dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in dirs {
            let full = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: full) {
                acpLog.debug("Resolved '\(name)' to \(full)")
                return full
            }
        }
        acpLog.error("'\(name)' not found in PATH — launch will likely fail")
        return name
    }

    nonisolated static func decodeText(from data: Data?) -> String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }
}

// MARK: - Errors

/// Chops-specific errors not covered by the SDK's errors.
enum ACPClientError: Error, LocalizedError {
    case agentNotConfigured(String)
    case noSession
    case terminalNotSupported

    var errorDescription: String? {
        switch self {
        case .agentNotConfigured(let id): "Agent '\(id)' not enabled. Go to Settings → ACP."
        case .noSession:                  "No active ACP session."
        case .terminalNotSupported:       "Terminal operations are not supported."
        }
    }
}
