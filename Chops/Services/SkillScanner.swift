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
            guard tool.isInstalled || tool.globalPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
                continue
            }
            for path in tool.globalPaths {
                let url = URL(fileURLWithPath: path)
                collectFromDirectory(url, toolSource: tool, isGlobal: true, into: &results)
            }
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

    /// Read and parse a single skill file. Pure I/O, no SwiftData.
    private static func collectSkillData(at fileURL: URL, toolSource: ToolSource, isDirectory: Bool, isGlobal: Bool) -> ScannedSkillData? {
        let fm = FileManager.default
        let resolved = fileURL.resolvingSymlinksInPath().path

        guard let parsed = SkillParser.parse(fileURL: fileURL, toolSource: toolSource) else {
            AppLogger.scanning.warning("Failed to parse: \(fileURL.path)")
            return nil
        }

        let attrs = try? fm.attributesOfItem(atPath: resolved)
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

    /// Apply collected results to SwiftData. Must be called on main thread.
    @MainActor
    private func applyResults(_ results: [ScannedSkillData]) {
        for data in results {
            let resolved = data.resolvedPath
            let predicate = #Predicate<Skill> { $0.resolvedPath == resolved }
            let descriptor = FetchDescriptor<Skill>(predicate: predicate)

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.content = data.content
                existing.name = data.name
                existing.skillDescription = data.skillDescription
                existing.frontmatter = data.frontmatter
                existing.fileModifiedDate = data.modDate
                existing.fileSize = data.fileSize
                existing.addInstallation(path: data.fileURL.path, tool: data.toolSource)
            } else {
                let skill = Skill(
                    filePath: data.fileURL.path,
                    toolSource: data.toolSource,
                    isDirectory: data.isDirectory,
                    name: data.name,
                    skillDescription: data.skillDescription,
                    content: data.content,
                    frontmatter: data.frontmatter,
                    fileModifiedDate: data.modDate,
                    fileSize: data.fileSize,
                    isGlobal: data.isGlobal,
                    resolvedPath: data.resolvedPath
                )
                modelContext.insert(skill)
            }
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
