import Foundation
import SwiftData
import os

struct ScannedMCPData: Sendable {
    let id: String
    let name: String
    let toolSource: ToolSource
    let configFilePath: String
    let transportType: String
    let command: String?
    let args: [String]
    let env: [String: String]
    let url: String?
    let headers: [String: String]
    let isEnabled: Bool
}

@Observable
final class MCPScanner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func scanAll() {
        let start = CFAbsoluteTimeGetCurrent()
        AppLogger.scanning.notice("MCP scan started")

        let customPaths = UserDefaults.standard.stringArray(forKey: "customScanPaths") ?? []
        Task.detached { [weak self] in
            let results = Self.collectAllMCPServers(customPaths: customPaths)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            AppLogger.scanning.notice("MCP collection done: \(results.count) servers in \(String(format: "%.2f", elapsed))s")

            await MainActor.run {
                guard let self else { return }
                self.applyResults(results)
                let total = CFAbsoluteTimeGetCurrent() - start
                AppLogger.scanning.notice("MCP scan complete: \(results.count) servers applied in \(String(format: "%.2f", total))s")
            }
        }
    }

    // MARK: - Collection (off main thread)

    /// Project-level MCP config paths to probe inside each project directory.
    private static let projectMCPProbes: [(subpath: String, tool: ToolSource)] = [
        (".cursor/mcp.json", .cursor),
        (".vscode/mcp.json", .copilot),
        (".claude/mcp.json", .claude),
    ]

    private static func collectAllMCPServers(customPaths: [String]) -> [ScannedMCPData] {
        var results: [ScannedMCPData] = []
        let fm = FileManager.default

        // Global tool configs
        for tool in ToolSource.allCases {
            for configPath in tool.mcpConfigPaths {
                let expanded = (configPath as NSString).expandingTildeInPath
                guard fm.fileExists(atPath: expanded) else { continue }
                collectFromConfig(path: expanded, toolSource: tool, into: &results)
            }
        }

        // Project-level configs inside custom scan directories
        for basePath in customPaths {
            guard let projects = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: basePath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for project in projects {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: project.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }

                for probe in projectMCPProbes {
                    let configPath = project.appendingPathComponent(probe.subpath).path
                    guard fm.fileExists(atPath: configPath) else { continue }
                    collectFromConfig(path: configPath, toolSource: probe.tool, into: &results)
                }
            }
        }

        return results
    }

    private static func collectFromConfig(path: String, toolSource: ToolSource, into results: inout [ScannedMCPData]) {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLogger.scanning.warning("Failed to parse MCP config: \(path)")
            return
        }

        if let servers = json["mcpServers"] as? [String: [String: Any]] {
            for (name, config) in servers {
                if let entry = parseServerEntry(name: name, config: config, toolSource: toolSource, configPath: path) {
                    results.append(entry)
                }
            }
        }

        // Claude Code: also scan per-project mcpServers
        if toolSource == .claude, let projects = json["projects"] as? [String: [String: Any]] {
            for (_, projectConfig) in projects {
                if let servers = projectConfig["mcpServers"] as? [String: [String: Any]] {
                    for (name, config) in servers {
                        let existingIDs = Set(results.map(\.id))
                        let candidateID = MCPServer.makeID(toolSource: toolSource, configFilePath: path, name: name)
                        guard !existingIDs.contains(candidateID) else { continue }
                        if let entry = parseServerEntry(name: name, config: config, toolSource: toolSource, configPath: path) {
                            results.append(entry)
                        }
                    }
                }
            }
        }
    }

    private static func parseServerEntry(name: String, config: [String: Any], toolSource: ToolSource, configPath: String) -> ScannedMCPData? {
        let command = config["command"] as? String
        let url = config["url"] as? String
        let args = config["args"] as? [String] ?? []
        let env = config["env"] as? [String: String] ?? [:]
        let headers = config["headers"] as? [String: String] ?? [:]

        let transportType: String
        if url != nil {
            if let urlStr = url, urlStr.contains("/sse") {
                transportType = "sse"
            } else {
                transportType = "http"
            }
        } else if command != nil {
            transportType = "stdio"
        } else {
            return nil
        }

        let isEnabled = (config["disabled"] as? Bool).map { !$0 } ?? true
        let id = MCPServer.makeID(toolSource: toolSource, configFilePath: configPath, name: name)

        return ScannedMCPData(
            id: id,
            name: name,
            toolSource: toolSource,
            configFilePath: configPath,
            transportType: transportType,
            command: command,
            args: args,
            env: env,
            url: url,
            headers: headers,
            isEnabled: isEnabled
        )
    }

    // MARK: - Apply (main thread)

    @MainActor
    private func applyResults(_ results: [ScannedMCPData]) {
        let descriptor = FetchDescriptor<MCPServer>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let scannedIDs = Set(results.map(\.id))

        for result in results {
            if let server = existingByID[result.id] {
                server.name = result.name
                server.toolSourceRaw = result.toolSource.rawValue
                server.configFilePath = result.configFilePath
                server.transportType = result.transportType
                server.command = result.command
                server.args = result.args
                server.env = result.env
                server.url = result.url
                server.headers = result.headers
                server.isEnabled = result.isEnabled
            } else {
                let server = MCPServer(
                    name: result.name,
                    toolSource: result.toolSource,
                    configFilePath: result.configFilePath,
                    transportType: result.transportType,
                    command: result.command,
                    args: result.args,
                    env: result.env,
                    url: result.url,
                    headers: result.headers,
                    isEnabled: result.isEnabled
                )
                modelContext.insert(server)
            }
        }

        for server in existing where !scannedIDs.contains(server.id) {
            modelContext.delete(server)
        }

        do { try modelContext.save() } catch {
            AppLogger.scanning.error("SwiftData save failed (MCP): \(error.localizedDescription)")
        }
    }
}
