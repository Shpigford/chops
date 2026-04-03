import Foundation

enum SSHError: LocalizedError {
    case connectionFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): "SSH connection failed: \(msg)"
        case .commandFailed(let msg): "SSH command failed: \(msg)"
        }
    }
}

enum SSHService {
    private static let sshPath = "/usr/bin/ssh"

    private static func baseArgs(for server: RemoteServer) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var args = [
            "-p", "\(server.port)",
            "-o", "ConnectTimeout=10",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
        ]

        if let keyPath = server.sshKeyPath, !keyPath.isEmpty {
            // User-specified key path (expand ~ if present)
            let resolved = keyPath.hasPrefix("~/")
                ? home + keyPath.dropFirst(1)
                : keyPath
            args += ["-i", resolved]
        } else {
            // Auto-discover common default key names
            let defaultKeys = ["id_ed25519", "id_rsa", "id_ecdsa"]
            for name in defaultKeys {
                let path = "\(home)/.ssh/\(name)"
                if FileManager.default.fileExists(atPath: path) {
                    args += ["-i", path]
                    break
                }
            }
        }

        args.append(server.sshDestination)
        return args
    }

    /// Escapes a string for safe use inside single quotes in a shell command.
    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Public API

    static func testConnection(_ server: RemoteServer) async throws {
        let (_, stderr, code) = try await run(
            args: baseArgs(for: server) + ["echo", "ok"]
        )
        if code != 0 {
            throw SSHError.connectionFailed(stderr)
        }
    }

    /// Escapes a path for the remote shell, handling tilde expansion.
    /// Uses double quotes so `$HOME` expands while spaces are preserved.
    private static func shellQuotePath(_ path: String) -> String {
        var expanded = path
        if expanded.hasPrefix("~/") {
            expanded = "$HOME/" + expanded.dropFirst(2)
        } else if expanded == "~" {
            expanded = "$HOME"
        }
        // Double-quote: preserves $HOME expansion, protects spaces and globs
        let escaped = expanded.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func findSkills(_ server: RemoteServer) async throws -> [(path: String, content: String)] {
        let basePath = shellQuotePath(server.skillsBasePath)

        // Find all SKILL.md files under the base path
        let findCmd = "find \(basePath) -name 'SKILL.md' -type f 2>/dev/null"
        let (stdout, stderr, code) = try await run(
            args: baseArgs(for: server) + [findCmd]
        )

        if code != 0 {
            throw SSHError.connectionFailed(stderr.isEmpty ? "Connection failed (exit code \(code))" : stderr)
        }

        let paths = stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if paths.isEmpty { return [] }

        // Read all files in a single SSH call
        let catCmds = paths.map { "echo '---CHOPS_DELIM:\($0)---' && cat \(shellEscape($0))" }
        let combined = catCmds.joined(separator: " && ")
        let (content, _, _) = try await run(
            args: baseArgs(for: server) + [combined]
        )

        return parseDelimitedOutput(content)
    }

    static func readFile(_ server: RemoteServer, path: String) async throws -> String {
        let (stdout, stderr, code) = try await run(
            args: baseArgs(for: server) + ["cat \(shellEscape(path))"]
        )
        if code != 0 {
            throw SSHError.commandFailed(stderr)
        }
        return stdout
    }

    static func writeFile(_ server: RemoteServer, path: String, content: String) async throws {
        // Ensure parent directory exists, then write via stdin
        let escaped = shellEscape(path)
        let mkdirCmd = "mkdir -p \"$(dirname \(escaped))\" && cat > \(escaped)"
        let (_, stderr, code) = try await run(
            args: baseArgs(for: server) + [mkdirCmd],
            stdin: content
        )
        if code != 0 {
            throw SSHError.commandFailed(stderr)
        }
    }

    // MARK: - Private

    private static func run(args: [String], stdin stdinContent: String? = nil) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: sshPath)
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                if let stdinContent {
                    let stdinPipe = Pipe()
                    process.standardInput = stdinPipe
                    let data = stdinContent.data(using: .utf8) ?? Data()
                    stdinPipe.fileHandleForWriting.write(data)
                    stdinPipe.fileHandleForWriting.closeFile()
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: (stdout, stderr, process.terminationStatus))
                } catch {
                    continuation.resume(throwing: SSHError.connectionFailed(error.localizedDescription))
                }
            }
        }
    }

    private static func parseDelimitedOutput(_ output: String) -> [(path: String, content: String)] {
        var results: [(path: String, content: String)] = []
        let lines = output.components(separatedBy: "\n")
        var currentPath: String?
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("---CHOPS_DELIM:") && line.hasSuffix("---") {
                // Save previous block
                if let path = currentPath {
                    results.append((path: path, content: currentLines.joined(separator: "\n")))
                }
                // Extract path from delimiter
                let start = line.index(line.startIndex, offsetBy: 15)
                let end = line.index(line.endIndex, offsetBy: -3)
                currentPath = String(line[start..<end])
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        // Save last block
        if let path = currentPath {
            results.append((path: path, content: currentLines.joined(separator: "\n")))
        }

        return results
    }
}
