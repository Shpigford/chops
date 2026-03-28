import Foundation
import os.log

/// Centralized ACP logging with optional debug mode and file storage
final class ACPLogger: @unchecked Sendable {
    static let shared = ACPLogger()

    private let osLog = Logger(subsystem: "md.chops", category: "ACP")
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "md.chops.acplogger", qos: .utility)
    private static let isoFormatter = ISO8601DateFormatter()
    private var fileHandle: FileHandle?

    /// Enable verbose debug logging (send/receive payloads)
    var debugEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "ACPDebugLogging") }
        set {
            UserDefaults.standard.set(newValue, forKey: "ACPDebugLogging")
            if newValue {
                info("Debug logging enabled")
            }
        }
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logsDir = appSupport.appendingPathComponent("Chops/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let filename = "acp-\(dateFormatter.string(from: Date())).log"
        logFileURL = logsDir.appendingPathComponent(filename)

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Public API

    func info(_ message: String) {
        log(level: .info, message: message)
    }

    func debug(_ message: String) {
        guard debugEnabled else { return }
        log(level: .debug, message: message)
    }

    func error(_ message: String) {
        log(level: .error, message: message)
    }

    enum Direction { case send, receive }

    /// Log a JSON-encodable value in debug mode. Centralises encoding so callers never duplicate it.
    func debugLogJSON<T: Encodable>(_ value: T, direction: Direction) {
        guard debugEnabled else { return }
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else { return }
        switch direction {
        case .send:    log(level: .debug, message: ">>> SEND: \(str)")
        case .receive: log(level: .debug, message: "<<< RECV: \(str)")
        }
    }

    /// Log send payload (only in debug mode)
    func logSend(_ payload: String) {
        guard debugEnabled else { return }
        log(level: .debug, message: ">>> SEND: \(payload)")
    }

    /// Log receive payload (only in debug mode)
    func logReceive(_ payload: String) {
        guard debugEnabled else { return }
        log(level: .debug, message: "<<< RECV: \(payload)")
    }

    /// Get the log file URL for viewing
    var logURL: URL { logFileURL }

    /// Get recent log content — runs on the logger's background queue, never blocks the caller.
    func recentLogs(lines: Int = 200) async -> String {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let data = try? Data(contentsOf: logFileURL),
                      let content = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: "(No logs available)")
                    return
                }
                let allLines = content.components(separatedBy: .newlines)
                let recentLines = allLines.suffix(lines)
                continuation.resume(returning: recentLines.joined(separator: "\n"))
            }
        }
    }

    /// Clear logs — truncates the file and writes a single marker entry.
    func clearLogs() {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileHandle?.truncate(atOffset: 0)
            self.fileHandle?.seek(toFileOffset: 0)
            // Call log() directly on the queue to avoid an extra async hop.
            let timestamp = Self.isoFormatter.string(from: Date())
            let line = "[\(timestamp)] [INFO] Logs cleared\n"
            if let data = line.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
            self.osLog.info("Logs cleared")
        }
    }

    // MARK: - Private

    private enum Level: String {
        case info = "INFO"
        case debug = "DEBUG"
        case error = "ERROR"
    }

    private func log(level: Level, message: String) {
        let timestamp = Self.isoFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"

        switch level {
        case .info: osLog.info("\(message)")
        case .debug: osLog.debug("\(message)")
        case .error: osLog.error("\(message)")
        }

        queue.async { [weak self] in
            if let data = line.data(using: .utf8) {
                self?.fileHandle?.write(data)
            }
        }
    }
}

// MARK: - Global convenience

let acpLog = ACPLogger.shared
