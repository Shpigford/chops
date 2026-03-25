import Foundation
import SwiftData
import os

/// Data collected from the filesystem for a single skill, before SwiftData persistence.
struct ScannedSkillData: Sendable {
    let fileURL: URL
    let resolvedPath: String
    let toolSource: ToolSource
    let isDirectory: Bool
    let isGlobal: Bool
    let name: String
    let skillDescription: String
    let content: String
    let frontmatter: [String: String]
    let modDate: Date
    let fileSize: Int
}

@Observable
final class SkillScanner {
    private let modelContext: ModelContext
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0

    /// Filenames that are tool config/meta files, not skills.
    private static let ignoredFileNames: Set<String> = [
        "README.md",
        "README",
        "CLAUDE.md",
        "AGENTS.md",
        "AGENTS.override.md",
        "global_rules.md",
        "SYSTEM.md",
        "APPEND_SYSTEM.md",
        "LICENSE.md",
        "LICENSE",
        "CHANGELOG.md",
    ]

    private static func shouldIgnoreLooseMarkdownFile(named fileName: String) -> Bool {
        return ignoredFileNames.contains(fileName)
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Project-level paths to probe inside each project directory
    private static let projectProbes: [(subpath: String, tool: ToolSource)] = [
        (".claude/skills", .claude),
        (".cursor/skills", .cursor),
        (".cursor/rules", .cursor),
        (".codex/skills", .codex),
        (".windsurf/rules", .windsurf),
        (".github", .copilot),
        (".config/amp/skills", .amp),
        (".opencode/skills", .opencode),
    ]

    func scanAll() {
        let start = CFAbsoluteTimeGetCurrent()
        AppLogger.scanning.notice("Scan started")

        scanTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        let customPaths = UserDefaults.standard.stringArray(forKey: "customScanPaths") ?? []
        scanTask = Task.detached { [weak self] in
            let results = Self.collectAllSkills(customPaths: customPaths)
            guard !Task.isCancelled else { return }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            AppLogger.scanning.notice("File collection done: \(results.count) skills in \(String(format: "%.2f", elapsed))s")

            await MainActor.run {
                guard let self, self.scanGeneration == generation else { return }
                self.applyResults(results)
                let total = CFAbsoluteTimeGetCurrent() - start
                AppLogger.scanning.notice("Scan complete: \(results.count) skills applied in \(String(format: "%.2f", total))s")
            }
        }
    }

    /// Pure filesystem I/O — safe to run off main thread.
    private static func collectAllSkills(customPaths: [String]) -> [ScannedSkillData] {
        var results: [ScannedSkillData] = []

        for tool in ToolSource.allCases where tool != .custom {
            guard !Task.isCancelled else { return results }
            guard tool.isInstalled else {
                continue
            }
            for path in tool.globalPaths {
                let url = URL(fileURLWithPath: path)
                collectFromDirectory(url, toolSource: tool, isGlobal: true, into: &results)
            }
        }

        // CLI plugins (installed_plugins.json)
        if ToolSource.claude.isInstalled {
            collectFromCLIPlugins(into: &results)
        }

        // Claude Desktop/Cowork plugin skills
        if ToolSource.claudeDesktop.isInstalled {
            collectClaudeDesktopSkills(into: &results)
        }

        for path in customPaths {
            guard !Task.isCancelled else { return results }
            collectFromCustomDirectory(URL(fileURLWithPath: path), into: &results)
        }

        return results
    }

    private static func collectFromCustomDirectory(_ directory: URL, into results: inout [ScannedSkillData]) {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for project in projects {
            guard !Task.isCancelled else { return }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: project.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            for probe in projectProbes {
                let probePath = project.appendingPathComponent(probe.subpath)
                guard fm.fileExists(atPath: probePath.path) else { continue }

                if probe.tool == .copilot {
                    let file = probePath.appendingPathComponent("copilot-instructions.md")
                    if fm.fileExists(atPath: file.path) {
                        if let data = collectSkillData(at: file, toolSource: .copilot, isDirectory: false, isGlobal: false) {
                            results.append(data)
                        }
                    }
                } else {
                    collectFromDirectory(probePath, toolSource: probe.tool, isGlobal: false, into: &results)
                }
            }
        }
    }

    private static func collectFromDirectory(_ directory: URL, toolSource: ToolSource, isGlobal: Bool, into results: inout [ScannedSkillData]) {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir) else { return }

        guard isDir.boolValue else { return }

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            guard !Task.isCancelled else { return }
            var itemIsDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &itemIsDir)

            if itemIsDir.boolValue {
                let skillFile = item.appendingPathComponent("SKILL.md")
                let agentsFile = item.appendingPathComponent("AGENTS.md")

                if fm.fileExists(atPath: skillFile.path) {
                    if let data = collectSkillData(at: skillFile, toolSource: toolSource, isDirectory: true, isGlobal: isGlobal) {
                        results.append(data)
                    }
                } else if fm.fileExists(atPath: agentsFile.path) {
                    if let data = collectSkillData(at: agentsFile, toolSource: toolSource, isDirectory: true, isGlobal: isGlobal) {
                        results.append(data)
                    }
                }
            } else if item.pathExtension == "md" || item.pathExtension == "mdc" {
                guard !shouldIgnoreLooseMarkdownFile(named: item.lastPathComponent) else { continue }
                if let data = collectSkillData(at: item, toolSource: toolSource, isDirectory: false, isGlobal: isGlobal) {
                    results.append(data)
                }
            }
        }
    }

    /// For Claude Desktop plugin paths, produce a canonical identity that strips volatile
    /// components (session IDs, version numbers). For all other tools, returns the normal
    /// symlink-resolved path. Same pattern as remote skills using `remote://` prefixes.
    private static func canonicalResolvedPath(for fileURL: URL, toolSource: ToolSource) -> String {
        let resolved = fileURL.resolvingSymlinksInPath().path
        let path = fileURL.path

        // CLI plugins: .../.claude/plugins/cache/<publisher>/<plugin>/<version>/skills/<skill>/SKILL.md
        if toolSource == .claude, let range = path.range(of: ".claude/plugins/cache/") {
            let after = String(path[range.upperBound...])
            let parts = after.components(separatedBy: "/")
            // parts: [publisher, plugin, version, "skills", skill, "SKILL.md"]
            guard parts.count >= 6, parts[3] == "skills" else { return resolved }
            return "claude-plugin:\(parts[0])/\(parts[1])/\(parts[4])"
        }

        guard toolSource == .claudeDesktop else { return resolved }

        // Local plugins: .../cowork_plugins/cache/<marketplace>/<plugin>/<version>/skills/<skill>/SKILL.md
        if let range = path.range(of: "cowork_plugins/cache/") {
            let after = String(path[range.upperBound...])
            let parts = after.components(separatedBy: "/")
            // parts: [marketplace, plugin, version, "skills", skill, "SKILL.md"]
            guard parts.count >= 6, parts[3] == "skills" else { return resolved }
            return "claude-desktop:cowork_plugins/\(parts[0])/\(parts[1])/\(parts[4])"
        }

        // Remote plugins: .../remote_cowork_plugins/<plugin-id>/skills/<skill>/SKILL.md
        if let range = path.range(of: "remote_cowork_plugins/") {
            let after = String(path[range.upperBound...])
            let parts = after.components(separatedBy: "/")
            // parts: [plugin-id, "skills", skill, "SKILL.md"]
            guard parts.count >= 4, parts[1] == "skills" else { return resolved }
            return "claude-desktop:remote_cowork_plugins/\(parts[0])/\(parts[2])"
        }

        return resolved
    }

    private static func isSyntheticLocalResolvedPath(_ resolvedPath: String) -> Bool {
        resolvedPath.hasPrefix("claude-plugin:") || resolvedPath.hasPrefix("claude-desktop:")
    }

    /// Read and parse a single skill file. Pure I/O, no SwiftData.
    private static func collectSkillData(at fileURL: URL, toolSource: ToolSource, isDirectory: Bool, isGlobal: Bool) -> ScannedSkillData? {
        let fm = FileManager.default
        let resolved = canonicalResolvedPath(for: fileURL, toolSource: toolSource)

        guard let parsed = SkillParser.parse(fileURL: fileURL, toolSource: toolSource) else {
            AppLogger.scanning.warning("Failed to parse: \(fileURL.path)")
            return nil
        }

        // Use the actual filesystem path for attributes (resolved may be a canonical identifier)
        let attrPath = fileURL.resolvingSymlinksInPath().path
        let attrs = try? fm.attributesOfItem(atPath: attrPath)
        let modDate = (attrs?[.modificationDate] as? Date) ?? .now
        let fileSize = (attrs?[.size] as? Int) ?? 0

        let name: String
        if !parsed.name.isEmpty {
            name = parsed.name
        } else if isDirectory {
            name = fileURL.deletingLastPathComponent().lastPathComponent
        } else {
            name = fileURL.deletingPathExtension().lastPathComponent
        }

        return ScannedSkillData(
            fileURL: fileURL,
            resolvedPath: resolved,
            toolSource: toolSource,
            isDirectory: isDirectory,
            isGlobal: isGlobal,
            name: name,
            skillDescription: parsed.description,
            content: parsed.content,
            frontmatter: parsed.frontmatter,
            modDate: modDate,
            fileSize: fileSize
        )
    }

    // MARK: - Claude Plugin Scanning

    /// Scan CLI plugins from ~/.claude/plugins/installed_plugins.json
    private static func collectFromCLIPlugins(into results: inout [ScannedSkillData]) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let jsonPath = "\(home)/.claude/plugins/installed_plugins.json"

        guard let data = fm.contents(atPath: jsonPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: [[String: Any]]] else { return }

        for (_, installations) in plugins {
            guard !Task.isCancelled else { return }
            for installation in installations {
                guard let installPath = installation["installPath"] as? String else { continue }
                let skillsDir = URL(fileURLWithPath: installPath).appendingPathComponent("skills")
                collectFromDirectory(skillsDir, toolSource: .claude, isGlobal: true, into: &results)
            }
        }
    }

    /// Scan Claude Desktop/Cowork plugin skills using manifests as source of truth.
    /// Only scans explicitly installed plugins — skips built-in Anthropic skills (skills-plugin/).
    private static func collectClaudeDesktopSkills(into results: inout [ScannedSkillData]) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let sessionsRoot = "\(home)/Library/Application Support/Claude/local-agent-mode-sessions"

        guard fm.fileExists(atPath: sessionsRoot) else { return }
        guard let sessionDirs = try? fm.contentsOfDirectory(atPath: sessionsRoot) else { return }

        for sessionDir in sessionDirs {
            guard !Task.isCancelled else { return }
            // Skip skills-plugin (Anthropic built-in skills, not user-installed)
            if sessionDir == "skills-plugin" { continue }

            let sessionPath = "\(sessionsRoot)/\(sessionDir)"
            guard let subDirs = try? fm.contentsOfDirectory(atPath: sessionPath) else { continue }

            for subDir in subDirs {
                guard !Task.isCancelled else { return }
                let subPath = "\(sessionPath)/\(subDir)"

                // Local cowork plugins: use installed_plugins.json as source of truth
                let installedJson = "\(subPath)/cowork_plugins/installed_plugins.json"
                if let data = fm.contents(atPath: installedJson),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let plugins = json["plugins"] as? [String: [[String: Any]]] {
                    for (_, installations) in plugins {
                        guard !Task.isCancelled else { return }
                        for installation in installations {
                            guard let installPath = installation["installPath"] as? String else { continue }
                            let skillsDir = URL(fileURLWithPath: installPath).appendingPathComponent("skills")
                            collectFromDirectory(skillsDir, toolSource: .claudeDesktop, isGlobal: true, into: &results)
                        }
                    }
                }

                // Remote cowork plugins: use manifest.json as source of truth
                let remoteDir = "\(subPath)/remote_cowork_plugins"
                let manifestPath = "\(remoteDir)/manifest.json"
                if let data = fm.contents(atPath: manifestPath),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let plugins = json["plugins"] as? [[String: Any]] {
                    for plugin in plugins {
                        guard !Task.isCancelled else { return }
                        guard let pluginId = plugin["id"] as? String else { continue }
                        let skillsDir = "\(remoteDir)/\(pluginId)/skills"
                        guard fm.fileExists(atPath: skillsDir) else { continue }
                        collectFromDirectory(
                            URL(fileURLWithPath: skillsDir),
                            toolSource: .claudeDesktop,
                            isGlobal: true,
                            into: &results
                        )
                    }
                }
            }
        }
    }

    /// Apply collected results to SwiftData. Must be called on main thread.
    @MainActor
    private func applyResults(_ results: [ScannedSkillData]) {
        let groupedResults = Dictionary(grouping: results, by: \.resolvedPath)
        let descriptor = FetchDescriptor<Skill>()
        let allSkills = (try? modelContext.fetch(descriptor)) ?? []
        let localSkills = allSkills.filter { !$0.isRemote }
        let existingByResolved = Dictionary(uniqueKeysWithValues: localSkills.map { ($0.resolvedPath, $0) })
        let scannedResolvedPaths = Set(groupedResults.keys)

        for (resolvedPath, installations) in groupedResults {
            guard let primary = installations.first else { continue }

            let installedPaths = Array(Set(installations.map(\.fileURL.path))).sorted()
            let toolSources = ToolSource.allCases.filter { tool in
                installations.contains { $0.toolSource == tool }
            }

            if let existing = existingByResolved[resolvedPath] {
                let preferredPath = installedPaths.contains(existing.filePath) ? existing.filePath : primary.fileURL.path
                let preferredData = installations.first(where: { $0.fileURL.path == preferredPath }) ?? primary

                existing.filePath = preferredPath
                existing.isDirectory = preferredData.isDirectory
                existing.name = preferredData.name
                existing.skillDescription = preferredData.skillDescription
                existing.content = preferredData.content
                existing.frontmatter = preferredData.frontmatter
                existing.fileModifiedDate = preferredData.modDate
                existing.fileSize = preferredData.fileSize
                existing.isGlobal = preferredData.isGlobal
                existing.installedPaths = installedPaths
                existing.toolSources = toolSources
            } else {
                let skill = Skill(
                    filePath: primary.fileURL.path,
                    toolSource: primary.toolSource,
                    isDirectory: primary.isDirectory,
                    name: primary.name,
                    skillDescription: primary.skillDescription,
                    content: primary.content,
                    frontmatter: primary.frontmatter,
                    fileModifiedDate: primary.modDate,
                    fileSize: primary.fileSize,
                    isGlobal: primary.isGlobal,
                    resolvedPath: primary.resolvedPath
                )
                skill.installedPaths = installedPaths
                skill.toolSources = toolSources
                modelContext.insert(skill)
            }
        }

        for skill in localSkills where !scannedResolvedPaths.contains(skill.resolvedPath) {
            modelContext.delete(skill)
        }

        try? modelContext.save()
    }

    // MARK: - Remote Server Scanning

    func syncAllRemoteServers() async {
        let descriptor = FetchDescriptor<RemoteServer>()
        guard let servers = try? modelContext.fetch(descriptor) else { return }
        for server in servers {
            await scanRemoteServer(server)
        }
    }

    /// Scans a remote server for skills. Sets lastSyncError on failure.
    func scanRemoteServer(_ server: RemoteServer) async {
        do {
            let remoteSkills = try await SSHService.findSkills(server)
            var foundPaths = Set<String>()

            for (path, content) in remoteSkills {
                let resolvedPath = "remote://\(server.id)/\(path)"
                foundPaths.insert(resolvedPath)

                let parsed = FrontmatterParser.parse(content)
                let name: String
                if !parsed.name.isEmpty {
                    name = parsed.name
                } else {
                    // Derive name from parent directory
                    let components = path.components(separatedBy: "/")
                    let skillDirIndex = components.lastIndex(of: "SKILL.md").map { components.index(before: $0) }
                    name = skillDirIndex.map { components[$0] } ?? "Unknown"
                }

                let predicate = #Predicate<Skill> { $0.resolvedPath == resolvedPath }
                let fetchDescriptor = FetchDescriptor<Skill>(predicate: predicate)

                if let existing = try? modelContext.fetch(fetchDescriptor).first {
                    existing.content = parsed.content
                    existing.name = name
                    existing.skillDescription = parsed.description
                    existing.frontmatter = parsed.frontmatter
                } else {
                    let skill = Skill(
                        filePath: resolvedPath,
                        toolSource: .openclaw,
                        isDirectory: true,
                        name: name,
                        skillDescription: parsed.description,
                        content: parsed.content,
                        frontmatter: parsed.frontmatter,
                        isGlobal: true,
                        resolvedPath: resolvedPath
                    )
                    skill.remoteServer = server
                    skill.remotePath = path
                    modelContext.insert(skill)
                }
            }

            // Remove skills that no longer exist on the server
            let serverID = server.id
            let remotePredicate = #Predicate<Skill> { $0.resolvedPath.starts(with: "remote://") }
            if let existingRemoteSkills = try? modelContext.fetch(FetchDescriptor<Skill>(predicate: remotePredicate)) {
                for skill in existingRemoteSkills {
                    guard skill.remoteServer?.id == serverID else { continue }
                    if !foundPaths.contains(skill.resolvedPath) {
                        modelContext.delete(skill)
                    }
                }
            }

            server.lastSyncDate = .now
            server.lastSyncError = nil
            try? modelContext.save()
        } catch {
            server.lastSyncError = error.localizedDescription
            try? modelContext.save()
        }
    }

    func removeDeletedSkills() {
        let descriptor = FetchDescriptor<Skill>()
        guard let skills = try? modelContext.fetch(descriptor) else { return }
        let fm = FileManager.default

        for skill in skills {
            // Remove orphaned remote skills (server was deleted)
            if skill.resolvedPath.hasPrefix("remote://") && skill.remoteServer == nil {
                modelContext.delete(skill)
                continue
            }

            // Remote skills are managed by scanRemoteServer(), skip here
            if skill.isRemote { continue }

            // Plugin skills use canonical IDs, not filesystem paths. Let applyResults()
            // handle their lifecycle so updates don't delete and recreate user metadata.
            if Self.isSyntheticLocalResolvedPath(skill.resolvedPath) { continue }

            // Remove previously-scanned loose markdown files that are now filtered out.
            let fileName = URL(fileURLWithPath: skill.filePath).lastPathComponent
            if !skill.isDirectory, Self.shouldIgnoreLooseMarkdownFile(named: fileName) {
                modelContext.delete(skill)
                continue
            }

            let validPaths = skill.installedPaths.filter { fm.fileExists(atPath: $0) }
            if validPaths.isEmpty {
                modelContext.delete(skill)
            } else {
                skill.installedPaths = validPaths
                if !fm.fileExists(atPath: skill.filePath), let first = validPaths.first {
                    skill.filePath = first
                }
            }
        }
        try? modelContext.save()
    }

    deinit {
        scanTask?.cancel()
    }
}
