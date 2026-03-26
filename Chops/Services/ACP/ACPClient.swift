import ACP
import Foundation

// MARK: - ACP Client

// MARK: - Non-Blocking Transport Wrapper

/// Wraps StdioTransport to make start() non-blocking.
/// The SDK's StdioTransport.start() blocks forever, which prevents connect() from completing.
/// `messages` is a stored property so the forwarding Task is created exactly once per connection.
final class NonBlockingTransport: Transport, @unchecked Sendable {
    private let wrapped: StdioTransport
    private var startTask: Task<Void, Error>?
    private var messagesTask: Task<Void, Never>?

    // Stored once — avoids spawning a new Task on every access of the computed property.
    let messages: AsyncStream<JsonRpcMessage>
    private let messagesContinuation: AsyncStream<JsonRpcMessage>.Continuation

    /// Called when the message forwarding loop exits (pipe closed / process died).
    /// ACPClient sets this to transition state to .disconnected without relying solely
    /// on terminationHandler, which fires only on process exit, not on a broken pipe.
    var onStreamEnd: (() -> Void)?

    init(input: FileHandle, output: FileHandle) {
        self.wrapped = StdioTransport(input: input, output: output)
        let (stream, continuation) = AsyncStream<JsonRpcMessage>.makeStream()
        self.messages = stream
        self.messagesContinuation = continuation
    }

    var state: AsyncStream<TransportState> {
        wrapped.state
    }

    func start() async throws {
        // Start the wrapped transport in a background task instead of blocking.
        startTask = Task {
            do {
                try await wrapped.start()
            } catch {
                acpLog.error("Transport error: \(error.localizedDescription)")
            }
        }
        // Begin forwarding messages (stores Task for cancellation on close).
        let wrappedRef = wrapped
        let continuation = messagesContinuation
        let streamEndCallback = onStreamEnd
        messagesTask = Task {
            for await message in wrappedRef.messages {
                acpLog.debugLogJSON(message, direction: .receive)
                continuation.yield(message)
            }
            continuation.finish()
            // Notify ACPClient that the pipe is closed, even if the process hasn't exited yet.
            streamEndCallback?()
        }
        // Give the transport a moment to initialise.
        try await Task.sleep(for: .milliseconds(50))
    }

    func send(_ message: JsonRpcMessage) async throws {
        acpLog.debugLogJSON(message, direction: .send)
        try await wrapped.send(message)
    }

    func close() async {
        startTask?.cancel()
        messagesTask?.cancel()
        messagesContinuation.finish()
        await wrapped.close()
    }
}

/// High-level client for interacting with ACP agents using the official SDK
@Observable
@MainActor
final class ACPClient {
    private var connection: ClientConnection?
    private var clientImpl: ChopsClient?
    private var sessionId: SessionId?
    private var process: Process?

    /// Current tool being used
    private(set) var currentTool: ToolSource?

    /// Connection state
    private(set) var state: ACPClientState = .disconnected

    /// Accumulated text response (fallback when agent streams without a file write)
    private(set) var responseText: String = ""

    /// Content proposed by the agent via fs/write_text_file (path → content)
    private(set) var pendingWrite: (path: String, content: String)?

    /// Error if any
    private(set) var lastError: Error?

    /// Timestamp of the most recent session update — used for adaptive silence detection.
    /// Reset at the start of each prompt; updated on every streaming event.
    private(set) var lastActivityDate: Date = .distantPast

    /// Background task running the current session/prompt request.
    /// ACPClient.prompt() fires this without awaiting so the caller's polling loop
    /// can drive the adaptive silence timeout independently of any SDK-internal timer.
    private var promptTask: Task<Void, Never>?

    /// Retry configuration
    private let maxRetries = 3
    private let baseRetryDelay: Double = 1.0

    // MARK: - Connection

    /// Connect to an ACP agent with automatic retry and exponential backoff
    func connect(tool: ToolSource, workingDirectory: URL) async throws {
        let config = ACPConfiguration.shared.config(for: tool)

        guard let config else {
            acpLog.error("Tool \(tool.displayName) not configured")
            throw ACPClientError.toolNotConfigured(tool)
        }

        guard config.enabled else {
            acpLog.error("Tool \(tool.displayName) not enabled")
            throw ACPClientError.toolNotConfigured(tool)
        }

        guard config.isValid else {
            acpLog.error("Binary not found: \(config.expandedBinaryPath)")
            throw ACPClientError.binaryNotFound(config.expandedBinaryPath)
        }

        state = .connecting
        currentTool = tool
        responseText = ""
        pendingWrite = nil
        lastError = nil

        var connectError: Error?

        for attempt in 1...maxRetries {
            do {
                try await attemptConnect(config: config, workingDirectory: workingDirectory)
                return
            } catch {
                connectError = error
                acpLog.debug("Attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    let backoff = baseRetryDelay * pow(2.0, Double(attempt - 1))
                    let jitter = Double.random(in: 0...0.5)
                    // Propagate cancellation — do not swallow CancellationError.
                    try await Task.sleep(for: .seconds(backoff + jitter))
                }
            }
        }

        state = .disconnected
        currentTool = nil
        lastError = connectError
        throw connectError ?? ACPClientError.connectionFailed
    }

    private func attemptConnect(config: ACPToolConfig, workingDirectory: URL) async throws {
        // Parse command and flags
        let flags = config.flags.split(separator: " ").map(String.init)

        // Create process using the SDK sample's pattern
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        // Use /usr/bin/env to resolve the command (handles Node.js scripts, etc.)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [config.expandedBinaryPath] + flags
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError  // Pass through stderr
        process.currentDirectoryURL = workingDirectory
        process.environment = buildEnvironment()

        // Monitor for unexpected process termination.
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let exitCode = proc.terminationStatus
                if self.state != .disconnected {
                    acpLog.info("Process \(proc.processIdentifier) exited (code: \(exitCode))")
                    self.state = .disconnected
                    self.currentTool = nil
                }
            }
        }

        try process.run()
        self.process = process

        // Create non-blocking transport (SDK's StdioTransport.start() blocks forever)
        let transport = NonBlockingTransport(
            input: stdoutPipe.fileHandleForReading,
            output: stdinPipe.fileHandleForWriting
        )
        // Detect pipe closure without relying solely on terminationHandler.
        transport.onStreamEnd = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.state != .disconnected else { return }
                acpLog.info("Transport stream closed — marking disconnected")
                self.state = .disconnected
                self.currentTool = nil
            }
        }

        // Create client implementation
        let client = ChopsClient(
            onSessionUpdate: { [weak self] update in
                Task { @MainActor in
                    self?.handleSessionUpdate(update)
                }
            },
            onFileWrite: { [weak self] path, content in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.pendingWrite != nil {
                        // Agent wrote a second file in the same turn; first write is replaced.
                        // Templates should instruct the agent to write only one file per turn.
                        acpLog.info("writeTextFile: overwriting pendingWrite (agent wrote multiple files in one turn)")
                    }
                    self.pendingWrite = (path: path, content: content)
                }
            }
        )
        self.clientImpl = client

        // Create connection
        let connection = ClientConnection(transport: transport, client: client)
        self.connection = connection

        // Connect with timeout
        let pid = process.processIdentifier
        let agentInfo: Implementation?
        do {
            agentInfo = try await withThrowingTaskGroup(of: Implementation?.self) { group in
                group.addTask {
                    try await connection.connect()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(60))
                    throw ACPClientError.timeout
                }
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw ACPClientError.connectionFailed
                }
                group.cancelAll()
                return result
            }
        } catch {
            // Terminate the child process so it does not become an orphan on retry.
            process.terminate()
            self.process = nil
            throw error
        }

        // Log connection success with agent info
        let agentName = agentInfo?.name ?? "unknown"
        let agentVersion = agentInfo?.version ?? "?"
        acpLog.info("Connected: \(agentName) v\(agentVersion) (PID: \(pid))")

        state = .connected
    }

    /// Disconnect from the agent
    func disconnect() async {
        let pid = process?.processIdentifier

        promptTask?.cancel()
        promptTask = nil
        await connection?.disconnect()
        process?.terminate()
        connection = nil
        clientImpl = nil
        sessionId = nil
        process = nil
        state = .disconnected
        currentTool = nil

        if let pid {
            acpLog.info("Disconnected: PID \(pid) terminated")
        }
    }

    // MARK: - Session

    /// Create a new session
    func createSession(cwd: URL) async throws -> SessionId {
        guard let connection, state == .connected else {
            throw ACPClientError.notConnected
        }

        let request = NewSessionRequest(cwd: cwd.path, mcpServers: [])
        let response = try await connection.createSession(request: request)
        self.sessionId = response.sessionId
        return response.sessionId
    }

    /// Clear the intercepted pending write so the next compose starts fresh.
    func clearPendingWrite() {
        pendingWrite = nil
    }

    /// Send a prompt to the agent.
    ///
    /// Returns immediately after firing the underlying JSON-RPC request in a background task.
    /// The caller is responsible for polling `state` and `lastActivityDate` to detect completion
    /// and to apply an adaptive silence timeout. This avoids any SDK-internal request timeout
    /// from interfering with long-running agent turns.
    func prompt(_ text: String) async throws {
        guard let connection, let sessionId else {
            throw ACPClientError.noSession
        }

        promptTask?.cancel()
        state = .prompting
        responseText = ""
        pendingWrite = nil
        lastActivityDate = Date()

        let request = PromptRequest(
            sessionId: sessionId,
            prompt: [.text(TextContent(text: text))]
        )

        // Fire without awaiting. The task transitions state to .connected when done
        // (whether the agent finished cleanly or the SDK timed out).
        promptTask = Task { [weak self] in
            do {
                _ = try await connection.prompt(request: request)
                acpLog.debug("Prompt completed (end_turn)")
            } catch {
                acpLog.error("Prompt ended with error: \(error.localizedDescription)")
            }
            await MainActor.run { [weak self] in
                guard let self, self.state == .prompting else { return }
                self.state = .connected
            }
        }
    }

    // MARK: - Session Update Handling

    private func handleSessionUpdate(_ update: SessionUpdate) {
        // Any event from the agent counts as activity; reset the silence timer.
        lastActivityDate = Date()

        switch update {
        case .agentMessageChunk(let chunk):
            if case .text(let textContent) = chunk.content {
                responseText += textContent.text
            }
        case .toolCall(let toolCall):
            acpLog.debug("Tool call: \(toolCall.title) [status: \(toolCall.status?.rawValue ?? "?")]")
        case .toolCallUpdate(let data):
            if let status = data.status {
                acpLog.debug("Tool update: \(data.toolCallId) [status: \(status.rawValue)]")
            }
        case .agentThoughtChunk:
            break  // internal reasoning; not user-visible
        default:
            break
        }
    }

    // MARK: - Environment

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let shellPath = Self.getUserShellPath() {
            env["PATH"] = shellPath
        }
        return env
    }

    /// Get PATH from user's environment (handles nvm, homebrew, etc.)
    static func getUserShellPath() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: [String] = []

        // nvm
        let nvmDir = "\(homeDir)/.nvm/versions/node"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            if let latest = contents.sorted().last {
                paths.append("\(nvmDir)/\(latest)/bin")
            }
        }

        // Common paths
        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "\(homeDir)/.volta/bin",
            "\(homeDir)/.claude/local",
            "\(homeDir)/.augment/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ])

        return paths.filter { FileManager.default.fileExists(atPath: $0) }.joined(separator: ":")
    }
}

// MARK: - ChopsClient (ACP Client Protocol Implementation)

/// Client implementation that receives session updates and handles permission requests.
///
/// Advertises `readTextFile` and `writeTextFile` capabilities so the agent can use
/// structured file-write calls. Writes are *intercepted* (not applied to disk) — the
/// ComposePanel presents them as a diff for the user to accept or reject.
final class ChopsClient: Client, ClientSessionOperations, @unchecked Sendable {
    private let onSessionUpdateHandler: @Sendable (SessionUpdate) -> Void
    /// Called when the agent issues `fs/write_text_file`. Second arg is the proposed content.
    private let onFileWriteHandler: @Sendable (String, String) -> Void

    init(
        onSessionUpdate: @escaping @Sendable (SessionUpdate) -> Void,
        onFileWrite: @escaping @Sendable (String, String) -> Void
    ) {
        self.onSessionUpdateHandler = onSessionUpdate
        self.onFileWriteHandler = onFileWrite
    }

    // MARK: - Client Protocol

    var capabilities: ClientCapabilities {
        ClientCapabilities(fs: FileSystemCapability(readTextFile: true, writeTextFile: true))
    }

    var info: Implementation? {
        Implementation(
            name: "Chops",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
    }

    // MARK: - Session Updates

    func onSessionUpdate(_ update: SessionUpdate) async {
        onSessionUpdateHandler(update)
    }

    // MARK: - FileSystemOperations

    /// Reads the file from disk so the agent sees the current on-disk content.
    /// Throws on failure so the agent receives a structured error rather than phantom empty content.
    func readTextFile(path: String, line: UInt32?, limit: UInt32?, meta: MetaField?) async throws -> ReadTextFileResponse {
        acpLog.debug("readTextFile: \(path)")
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            return ReadTextFileResponse(content: content)
        } catch {
            acpLog.error("readTextFile failed: \(path) — \(error.localizedDescription)")
            throw error
        }
    }

    /// Intercepts the agent's write without touching the disk.
    /// The proposed content is surfaced to the ComposePanel as a diff.
    func writeTextFile(path: String, content: String, meta: MetaField?) async throws -> WriteTextFileResponse {
        acpLog.info("Write intercepted: \(path)")
        onFileWriteHandler(path, content)
        return WriteTextFileResponse()
    }

    // MARK: - ClientSessionOperations

    func requestPermissions(
        toolCall: ToolCallUpdateData,
        permissions: [PermissionOption],
        meta: MetaField?
    ) async throws -> RequestPermissionResponse {
        acpLog.info("Permission request: \(toolCall.title ?? "tool")")
        acpLog.debug("Options: \(permissions.map { $0.optionId })")

        if let allowOption = permissions.first(where: { $0.kind == .allowOnce || $0.kind == .allowAlways }) {
            acpLog.info("Auto-approved: \(allowOption.optionId)")
            return RequestPermissionResponse(outcome: .selected(allowOption.optionId))
        }
        if let firstOption = permissions.first {
            return RequestPermissionResponse(outcome: .selected(firstOption.optionId))
        }
        acpLog.error("No permission options available")
        return RequestPermissionResponse(outcome: .cancelled)
    }

    func notify(notification: SessionUpdate, meta: MetaField?) async {
        onSessionUpdateHandler(notification)
    }
}

// MARK: - State & Errors

enum ACPClientState {
    case disconnected
    case connecting
    case connected
    case prompting
}

enum ACPClientError: Error, LocalizedError {
    case toolNotConfigured(ToolSource)
    case binaryNotFound(String)
    case connectionFailed
    case initializationFailed(String)
    case notConnected
    case noSession
    case invalidResponse
    case agentError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .toolNotConfigured(let tool):
            "\(tool.displayName) ACP not configured. Go to Settings → ACP to configure."
        case .binaryNotFound(let path):
            "ACP binary not found at: \(path)"
        case .connectionFailed:
            "Failed to connect to ACP agent after multiple attempts"
        case .initializationFailed(let msg):
            "ACP initialization failed: \(msg)"
        case .notConnected:
            "Not connected to ACP agent"
        case .noSession:
            "No active ACP session"
        case .invalidResponse:
            "Invalid response from ACP agent"
        case .agentError(let msg):
            "Agent error: \(msg)"
        case .timeout:
            "Operation timed out"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .toolNotConfigured:
            "Open Settings and configure the ACP binary path and flags."
        case .binaryNotFound:
            "Verify the binary path in Settings → ACP and ensure the tool is installed."
        case .connectionFailed, .initializationFailed:
            "Try restarting the ACP tool or check its logs for errors."
        default:
            nil
        }
    }
}


