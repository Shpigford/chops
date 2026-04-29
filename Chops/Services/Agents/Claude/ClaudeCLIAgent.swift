import Foundation
import Observation

/// One-shot transport for Claude Code. Each `prompt()` is a single `claude --print
/// --output-format json` invocation: send the system prompt + current file content +
/// user request, wait for the response, parse out a fenced code block as the proposed
/// new file content, build a `PendingWrite` for the existing diff-review UI to gate.
///
/// Chops owns the disk write — Claude never touches the file. That's the simple,
/// reliable contract: ask Claude what the file should look like; show the diff; if
/// the user approves, *we* write it.
@Observable
@MainActor
final class ClaudeCLIAgent: AgentSession {

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
    private var currentTurnTask: Task<Void, Never>?
    private var promptWasCancelled = false

    // MARK: - Lifecycle

    func startConnect(workingDirectory: URL, systemPrompt: String?) {
        self.workingDirectory = workingDirectory
        self.sessionSystemPrompt = systemPrompt
        self.lastError = nil
        guard ToolSource.claude.cliBinaryURL != nil else {
            lastError = AgentError.binaryNotInstalled(
                toolName: "Claude Code",
                installURL: URL(string: "https://claude.ai/download")!
            ).localizedDescription
            return
        }
        isConnected = true
    }

    func disconnect() async {
        currentTurnTask?.cancel()
        currentProcess?.terminate()
        currentTurnTask = nil
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
        guard let bin = ToolSource.claude.cliBinaryURL,
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
            title: "Thinking with Claude…",
            status: .running
        ))
        currentActivity = "Thinking with Claude…"

        defer {
            isProcessing = false
            turnStartedAt = nil
            currentActivity = nil
        }

        let (filePath, fileContent) = primaryFile()
        let userMessage = OneShotPrompts.userMessage(
            userRequest: text,
            filePath: filePath,
            fileContent: fileContent
        )
        let systemPrompt = sessionSystemPrompt ?? OneShotPrompts.defaultSystemPrompt(filePath: filePath)

        do {
            let result = try await runClaudeOneshot(
                bin: bin,
                workingDir: wd,
                systemPrompt: systemPrompt,
                userMessage: userMessage
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
        currentTurnTask?.cancel()
    }

    // MARK: - Permissions / writes (mostly no-ops in one-shot mode)

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
        // Single-file flows store both the literal and resolved-symlink path so callers
        // can look up by either. ComposePanel only ever primes the file currently in
        // the editor, so primaryFile() picks it up reliably.
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

    private func runClaudeOneshot(
        bin: URL,
        workingDir: URL,
        systemPrompt: String,
        userMessage: String
    ) async throws -> String {
        let proc = Process()
        proc.executableURL = bin
        // `--settings` overrides ~/.claude/settings.json for THIS session only. We
        // force effortLevel="low" so the user's global "high" doesn't make every Chops
        // turn burn 5+ minutes on extended thinking for trivial markdown edits. We
        // skip merging the user's hooks/plugins because they'd add overhead for short
        // edit-style turns (the user's terminal claude is unaffected).
        let sessionSettings = #"{"effortLevel":"low","permissions":{"dangerouslySkipPermissions":false},"includeCoAuthoredBy":false}"#
        // Do NOT pass `--add-dir` — it's variadic and silently consumes the positional
        // prompt arg that follows. `--tools ""` disables tool use so Claude cannot write
        // behind Chops' diff review; `--` keeps the prompt out of that variadic option.
        proc.arguments = [
            "-p",
            "--output-format", "json",
            "--system-prompt", systemPrompt,
            "--model", "sonnet",
            "--settings", sessionSettings,
            "--tools", "",
            "--",
            userMessage,
        ]

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env["CLAUDE_CODE_ENTRYPOINT"] = "sdk-swift"
        env["CLAUDE_AGENT_SDK_VERSION"] = "0.2.121"
        proc.environment = env
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

        // Read pipes off the main actor and concurrently. A verbose stderr stream can
        // otherwise fill its pipe and block the child before stdout closes.
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
            agentLog.info("Claude stdout (\(stdoutData.count)B): \(s.prefix(2000))")
        }
        if let s = String(data: errData, encoding: .utf8), !s.isEmpty {
            agentLog.info("Claude stderr: \(s.prefix(2000))")
        }
        agentLog.info("Claude exit=\(proc.terminationStatus)")

        if proc.terminationStatus != 0 {
            let errText = String(data: errData, encoding: .utf8) ?? ""
            let trimmed = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentError.launchFailed(
                "Claude exited with code \(proc.terminationStatus)" +
                (trimmed.isEmpty ? "" : ":\n\(trimmed.suffix(800))")
            )
        }

        struct PrintResult: Decodable {
            let result: String?
            let is_error: Bool?
            let total_cost_usd: Double?
        }

        do {
            let envelope = try JSONDecoder().decode(PrintResult.self, from: stdoutData)
            if envelope.is_error == true {
                throw AgentError.launchFailed(envelope.result ?? "Claude reported an error")
            }
            return envelope.result ?? ""
        } catch {
            let preview = String(data: stdoutData.prefix(400), encoding: .utf8) ?? "<non-utf8>"
            throw AgentError.launchFailed("Couldn't parse Claude's reply. First 400 bytes:\n\(preview)")
        }
    }
}
