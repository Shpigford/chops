import Foundation
import Observation

/// One-shot transport for OpenAI Codex. Each `prompt()` is a single
/// `codex exec --output-last-message <tmp> --sandbox read-only --skip-git-repo-check
/// --ephemeral <user-message>` invocation. Codex never touches the filesystem; Chops
/// owns the disk write the same way the Claude transport does.
@Observable
@MainActor
final class CodexCLIAgent: AgentSession {

    // MARK: - AgentSession state

    var responseText: String = ""
    var thoughtText: String = ""
    var currentActivity: String? = nil
    var pendingWrites: [PendingWrite] = []
    var deferredContent: [String: String] = [:]
    private(set) var pendingPermissionRequest: PermissionRequest? = nil
    private(set) var isConnected: Bool = false
    private(set) var isConnecting: Bool = false
    private(set) var isProcessing: Bool = false
    private(set) var turnStartedAt: Date? = nil
    private(set) var activities: [AgentActivity] = []
    private(set) var lastError: String? = nil
    var isBypassMode: Bool = false  // unused in one-shot mode

    // MARK: - Private

    private var workingDirectory: URL?
    private var sessionSystemPrompt: String?
    private var currentProcess: Process?
    private var promptWasCancelled = false

    // MARK: - Lifecycle

    func startConnect(workingDirectory: URL, systemPrompt: String?) {
        self.workingDirectory = workingDirectory
        self.sessionSystemPrompt = systemPrompt
        self.lastError = nil
        guard ToolSource.codex.cliBinaryURL != nil else {
            lastError = AgentError.binaryNotInstalled(
                toolName: "Codex",
                installURL: URL(string: "https://github.com/openai/codex/releases")!
            ).localizedDescription
            return
        }
        isConnected = true
    }

    func disconnect() async {
        currentProcess?.terminate()
        currentProcess = nil
        if let req = pendingPermissionRequest {
            pendingPermissionRequest = nil
            req.continuation.resume(returning: .cancelled)
        }
        isConnected = false
        isProcessing = false
        turnStartedAt = nil
        responseText = ""
        thoughtText = ""
        currentActivity = nil
        activities = []
        pendingWrites = []
        deferredContent = [:]
        lastError = nil
        workingDirectory = nil
        sessionSystemPrompt = nil
    }

    // MARK: - Per-turn

    func prompt(_ text: String) async throws {
        guard let bin = ToolSource.codex.cliBinaryURL,
              let wd = workingDirectory else {
            throw AgentError.noSession
        }

        responseText = ""
        thoughtText = ""
        pendingWrites = []
        currentActivity = nil
        activities = []
        turnStartedAt = Date()
        isProcessing = true
        promptWasCancelled = false

        let activityId = UUID()
        activities.append(AgentActivity(
            id: activityId,
            kind: .thinking,
            title: "Thinking with Codex…",
            status: .running
        ))
        currentActivity = "Thinking with Codex…"

        defer {
            isProcessing = false
            turnStartedAt = nil
            currentActivity = nil
        }

        let (filePath, fileContent) = primaryFile()
        // Codex doesn't accept a separate system prompt flag, so we splice it into the
        // user message — same shape that worked end-to-end in CLI smoke tests.
        let systemPrompt = sessionSystemPrompt ?? OneShotPrompts.defaultSystemPrompt(filePath: filePath)
        let userBody = OneShotPrompts.userMessage(
            userRequest: text,
            filePath: filePath,
            fileContent: fileContent
        )
        let combined = "\(systemPrompt)\n\n---\n\n\(userBody)"

        do {
            let result = try await runCodexOneshot(
                bin: bin,
                workingDir: wd,
                userMessage: combined
            )

            let parsed = OneShotResponseParser.parse(result, originalContent: fileContent)
            responseText = parsed.summary

            guard let newContent = parsed.newContent,
                  let filePath, let fileContent,
                  newContent != fileContent else {
                if responseText.isEmpty {
                    responseText = result.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let i = activities.firstIndex(where: { $0.id == activityId }) {
                    activities[i].status = .done
                    activities[i].title = "Replied"
                }
                return
            }

            let resolvedPath = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
            pendingWrites.append(PendingWrite(
                path: filePath,
                content: newContent,
                originalText: fileContent,
                originalData: fileContent.data(using: .utf8),
                existedBefore: FileManager.default.fileExists(atPath: resolvedPath),
                agentDidWrite: false
            ))

            if let i = activities.firstIndex(where: { $0.id == activityId }) {
                activities[i].status = .done
                activities[i].title = "Proposed edit ready"
            }
        } catch is CancellationError {
            if let i = activities.firstIndex(where: { $0.id == activityId }) {
                activities[i].status = .failed
                activities[i].title = "Cancelled"
            }
            throw CancellationError()
        } catch {
            if let i = activities.firstIndex(where: { $0.id == activityId }) {
                activities[i].status = .failed
                activities[i].title = "Failed"
                activities[i].detail = error.localizedDescription
            }
            throw error
        }
    }

    func cancelPrompt() {
        promptWasCancelled = true
        currentProcess?.terminate()
    }

    // MARK: - Permissions / writes (no-op in one-shot mode — we own disk writes)

    func respondToPermission(optionId: String?) {
        guard let req = pendingPermissionRequest else { return }
        pendingPermissionRequest = nil
        if let id = optionId {
            req.continuation.resume(returning: .choice(id))
        } else {
            req.continuation.resume(returning: .cancelled)
        }
    }

    func clearPendingWrites() {
        pendingWrites = []
        deferredContent = [:]
    }

    func primeDeferredContent(for path: String, content: String) {
        deferredContent[path] = content
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != path { deferredContent[resolved] = content }
    }

    func conversationalText(from text: String) -> String { text }

    // MARK: - Internals

    private func primaryFile() -> (path: String?, content: String?) {
        if let entry = deferredContent.first {
            return (entry.key, entry.value)
        }
        return (nil, nil)
    }

    private func runCodexOneshot(
        bin: URL,
        workingDir: URL,
        userMessage: String
    ) async throws -> String {
        // `--output-last-message` is the cleanest way to get just the final agent reply.
        // Stdout interleaves status lines, "tokens used", colorised banners, etc.; the
        // file gets exactly the last assistant message and nothing else.
        let lastMsgURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chops-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: lastMsgURL) }

        let proc = Process()
        proc.executableURL = bin
        proc.arguments = [
            "exec",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--ephemeral",
            "--color", "never",
            "--output-last-message", lastMsgURL.path,
            userMessage,
        ]

        proc.environment = ProcessInfo.processInfo.environment
        proc.currentDirectoryURL = workingDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            throw AgentError.launchFailed(error.localizedDescription)
        }
        currentProcess = proc
        defer { currentProcess = nil }

        // Read pipes concurrently. If stderr fills while stdout is still open, waiting on
        // stdout first can deadlock the turn.
        async let stdoutRead: Data = Task.detached(priority: .userInitiated) {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        async let stderrRead: Data = Task.detached(priority: .utility) {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        await Task.detached(priority: .utility) {
            proc.waitUntilExit()
        }.value

        let (stdoutData, errData) = await (stdoutRead, stderrRead)

        if Task.isCancelled || promptWasCancelled { throw CancellationError() }

        if let s = String(data: stdoutData, encoding: .utf8) {
            agentLog.info("Codex stdout (\(stdoutData.count)B): \(s.prefix(2000))")
        }
        if let s = String(data: errData, encoding: .utf8), !s.isEmpty {
            agentLog.info("Codex stderr: \(s.prefix(2000))")
        }
        agentLog.info("Codex exit=\(proc.terminationStatus)")

        if proc.terminationStatus != 0 {
            let errText = String(data: errData, encoding: .utf8) ?? ""
            let trimmed = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentError.launchFailed(
                "Codex exited with code \(proc.terminationStatus)" +
                (trimmed.isEmpty ? "" : ":\n\(trimmed.suffix(800))")
            )
        }

        guard let lastMsg = try? String(contentsOf: lastMsgURL, encoding: .utf8),
              !lastMsg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let preview = String(data: stdoutData.prefix(400), encoding: .utf8) ?? "<non-utf8>"
            throw AgentError.launchFailed("Codex returned no final message. First 400 bytes of stdout:\n\(preview)")
        }
        return lastMsg
    }
}
