import AppKit
import Foundation
import OSLog
import SwiftData

enum DiagnosticExporter {
    static func export(modelContext: ModelContext) {
        var lines: [String] = []

        // System info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        lines.append("# Chops Diagnostic Report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: .now))")
        lines.append("")
        lines.append("## System")
        lines.append("- App Version: \(version) (\(build))")
        lines.append("- macOS: \(osVersion)")
        lines.append("- Memory: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB")
        lines.append("")

        // Skill counts
        let descriptor = FetchDescriptor<Skill>()
        let skills = (try? modelContext.fetch(descriptor)) ?? []
        lines.append("## Skills")
        lines.append("- Total: \(skills.count)")
        for tool in ToolSource.allCases {
            let count = skills.filter { $0.toolSources.contains(tool) }.count
            if count > 0 {
                lines.append("- \(tool.displayName): \(count)")
            }
        }
        lines.append("")

        // Custom scan paths
        let customPaths = UserDefaults.standard.stringArray(forKey: "customScanPaths") ?? []
        lines.append("## Custom Scan Paths")
        if customPaths.isEmpty {
            lines.append("- (none)")
        } else {
            for path in customPaths {
                lines.append("- \(path)")
            }
        }
        lines.append("")

        // Recent logs
        lines.append("## Recent Logs")
        if let logEntries = collectRecentLogs() {
            lines.append(logEntries)
        } else {
            lines.append("(Unable to collect logs)")
        }

        let report = lines.joined(separator: "\n")

        // Save panel
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "chops-diagnostic-\(dateStamp()).txt"
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func collectRecentLogs() -> String? {
        // Try system scope first (persisted logs, survives force quit)
        // Fall back to current process scope
        let store: OSLogStore
        if let systemStore = try? OSLogStore(scope: .system) {
            store = systemStore
        } else if let processStore = try? OSLogStore(scope: .currentProcessIdentifier) {
            store = processStore
        } else {
            return nil
        }

        let since = Date.now.addingTimeInterval(-3600) // last hour
        let subsystem = Bundle.main.bundleIdentifier ?? "com.shpigford.Chops"

        guard let entries = try? store.getEntries(
            at: store.position(date: since),
            matching: NSPredicate(format: "subsystem == %@", subsystem)
        ) else {
            return nil
        }

        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            let time = formatter.string(from: logEntry.date)
            lines.append("[\(time)] [\(logEntry.category)] \(logEntry.composedMessage)")
        }

        return lines.isEmpty ? "(No log entries in the last hour)" : lines.joined(separator: "\n")
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: .now)
    }
}
