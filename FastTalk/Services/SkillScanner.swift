import Foundation
import SwiftData
import os

struct NoteMetadata: Sendable {
    let title: String
    let excerpt: String
}

enum NotesService {
    static let untitledTitle = "Untitled Note"
    static let initialContent = "# "

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd--HH-mm-ss"
        return formatter
    }()

    static var notesDirectoryURL: URL {
        let fm = FileManager.default
        let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return documentsURL
            .appendingPathComponent("fntalk", isDirectory: true)
            .appendingPathComponent("notes", isDirectory: true)
    }

    static var notesDirectoryPath: String { notesDirectoryURL.path }

    static func notesDirectoryExists() -> Bool {
        FileManager.default.fileExists(atPath: notesDirectoryPath)
    }

    static func ensureNotesDirectoryExists() throws {
        try FileManager.default.createDirectory(at: notesDirectoryURL, withIntermediateDirectories: true)
    }

    static func createBlankNote() throws -> URL {
        try ensureNotesDirectoryExists()

        let fm = FileManager.default
        let timestamp = fileNameDateFormatter.string(from: Date())
        var collisionIndex = 0

        while true {
            let collisionSuffix = collisionIndex == 0 ? "" : "-\(collisionIndex)"
            let name = "\(timestamp)\(collisionSuffix).md"
            let fileURL = notesDirectoryURL.appendingPathComponent(name)
            guard !fm.fileExists(atPath: fileURL.path) else {
                collisionIndex += 1
                continue
            }
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }
    }

    static func metadata(for content: String) -> NoteMetadata {
        let lines = content.components(separatedBy: .newlines)
        let meaningfulLines = lines.enumerated().compactMap { index, line -> (Int, String)? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return (index, trimmed)
        }

        guard let firstLine = meaningfulLines.first else {
            return NoteMetadata(title: untitledTitle, excerpt: "")
        }

        let headingLine = meaningfulLines.first { headingTitle(from: $0.1) != nil }
        let titleSource = headingLine ?? firstLine
        let title: String

        if let headingTitle = headingTitle(from: titleSource.1), !headingTitle.isEmpty {
            title = headingTitle
        } else {
            let fallbackTitle = normalizedDisplayLine(from: titleSource.1)
            title = truncatedFallbackTitle(from: fallbackTitle)
        }

        let excerpt = (
            meaningfulLines.first(where: { $0.0 > titleSource.0 })?.1
        )
        .map(normalizedDisplayLine) ?? ""

        return NoteMetadata(
            title: title.isEmpty ? untitledTitle : title,
            excerpt: excerpt
        )
    }

    static func makeIndexedNote(
        fileURL: URL,
        content: String,
        fileModifiedDate: Date,
        fileSize: Int
    ) -> Skill {
        let metadata = self.metadata(for: content)
        let note = Skill(
            filePath: fileURL.path,
            toolSource: .custom,
            isDirectory: false,
            name: metadata.title,
            skillDescription: metadata.excerpt,
            content: content,
            frontmatter: [:],
            fileModifiedDate: fileModifiedDate,
            fileSize: fileSize,
            isGlobal: true,
            resolvedPath: fileURL.path,
            kind: .note
        )
        note.installedPaths = [fileURL.path]
        note.toolSources = [.custom]
        return note
    }

    private static func normalizedDisplayLine(from rawLine: String) -> String {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedHeading = trimmed.replacingOccurrences(
            of: #"^#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )
        return strippedHeading.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func headingTitle(from rawLine: String) -> String? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let match = trimmed.range(
                of: #"^#{1,4}\s+.+$"#,
                options: .regularExpression
            )
        else {
            return nil
        }

        let heading = String(trimmed[match])
        let normalized = normalizedDisplayLine(from: heading)
        return normalized.isEmpty ? nil : normalized
    }

    private static func truncatedFallbackTitle(from line: String) -> String {
        guard line.count > 20 else { return line }
        return "\(line.prefix(20))..."
    }
}

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
    let kind: ItemKind
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
    private static let projectProbes: [(subpath: String, tool: ToolSource, kind: ItemKind)] = [
        (".claude/skills", .claude, .skill),
        (".claude/agents", .claude, .agent),
        (".cursor/skills", .cursor, .skill),
        (".cursor/rules", .cursor, .rule),
        (".cursor/agents", .cursor, .agent),
        (".codex/skills", .codex, .skill),
        (".codex/agents", .codex, .agent),
        (".windsurf/rules", .windsurf, .rule),
        (".github", .copilot, .skill),
        (".github/agents", .copilot, .agent),
        (".config/amp/skills", .amp, .skill),
        (".opencode/skills", .opencode, .skill),
    ]

    func scanAll() {
        let start = CFAbsoluteTimeGetCurrent()
        AppLogger.scanning.notice("Scan started")

        scanTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        let customPaths = UserDefaults.standard.stringArray(forKey: "customScanPaths") ?? []
        let includePlugins = FastTalkSettings.includePluginSkills
        scanTask = Task.detached { [weak self] in
            let results = Self.collectAllSkills(customPaths: customPaths, includePlugins: includePlugins)
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
    private static func collectAllSkills(customPaths: [String], includePlugins: Bool) -> [ScannedSkillData] {
        var results: [ScannedSkillData] = []

        for tool in ToolSource.allCases where tool != .custom {
            guard !Task.isCancelled else { return results }
            guard tool.isInstalled else {
                continue
            }
            for path in tool.globalPaths {
                let url = URL(fileURLWithPath: path)
                collectFromDirectory(url, toolSource: tool, isGlobal: true, kind: .skill, into: &results)
            }
            for path in tool.globalAgentPaths {
                let url = URL(fileURLWithPath: path)
                collectFromDirectory(url, toolSource: tool, isGlobal: true, kind: .agent, into: &results)
            }
            for path in tool.globalRulePaths {
                let url = URL(fileURLWithPath: path)
                collectFromDirectory(url, toolSource: tool, isGlobal: true, kind: .rule, into: &results)
            }
        }

        if NotesService.notesDirectoryExists() {
            collectFromDirectory(NotesService.notesDirectoryURL, toolSource: .custom, isGlobal: true, kind: .note, into: &results)
        }

        if includePlugins {
            // CLI plugins (installed_plugins.json)
            if ToolSource.claude.isInstalled {
                collectFromCLIPlugins(into: &results)
            }
            // Claude Desktop/Cowork plugin skills
            if ToolSource.claudeDesktop.isInstalled {
                collectClaudeDesktopSkills(into: &results)
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

        collectDirectSkillsFromCustomDirectory(directory, into: &results)

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

                if probe.tool == .copilot && probe.kind == .skill {
                    let file = probePath.appendingPathComponent("copilot-instructions.md")
                    if fm.fileExists(atPath: file.path) {
                        if let data = collectSkillData(at: file, toolSource: .copilot, isDirectory: false, isGlobal: false, kind: probe.kind) {
                            results.append(data)
                        }
                    }
                } else {
                    collectFromDirectory(probePath, toolSource: probe.tool, isGlobal: false, kind: probe.kind, into: &results)
                }
            }
        }
    }

    /// Custom scan paths serve two different jobs:
    /// - parent dirs like ~/Development that contain projects with tool-specific folders
    /// - library dirs that contain skills directly as child folders/files
    ///
    /// Only scan direct skill-style entries here so repo-level AGENTS.md files do not become
    /// bogus custom skills when the user adds a generic project parent directory.
    private static func collectDirectSkillsFromCustomDirectory(_ directory: URL, into results: inout [ScannedSkillData]) {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            guard !Task.isCancelled else { return }

            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                let skillFile = item.appendingPathComponent("SKILL.md")
                guard fm.fileExists(atPath: skillFile.path) else { continue }
                if let data = collectSkillData(
                    at: skillFile,
                    toolSource: .custom,
                    isDirectory: true,
                    isGlobal: false,
                    kind: .skill
                ) {
                    results.append(data)
                }
            } else {
                guard ["md", "mdc", "toml"].contains(item.pathExtension) else { continue }
                guard !shouldIgnoreLooseMarkdownFile(named: item.lastPathComponent) else { continue }
                if let data = collectSkillData(
                    at: item,
                    toolSource: .custom,
                    isDirectory: false,
                    isGlobal: false,
                    kind: .skill
                ) {
                    results.append(data)
                }
            }
        }
    }

    private static func collectFromDirectory(_ directory: URL, toolSource: ToolSource, isGlobal: Bool, kind: ItemKind = .skill, into results: inout [ScannedSkillData]) {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir) else { return }

        guard isDir.boolValue else { return }

        // Enumerate through the resolved directory so symlinked directories are traversed.
        let resolvedDirectory = directory.resolvingSymlinksInPath()

        guard let contents = try? fm.contentsOfDirectory(
            at: resolvedDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // Track both bases so each entry can be remapped back to the canonical path for storage.
        let originalBase = directory.path
        let resolvedBase = resolvedDirectory.path

        for rawItem in contents {
            guard !Task.isCancelled else { return }
            // Remap to canonical path for storage; use rawItem for filesystem operations.
            let item: URL
            if originalBase != resolvedBase, rawItem.path.hasPrefix(resolvedBase + "/") {
                let suffix = String(rawItem.path.dropFirst(resolvedBase.count))
                item = URL(fileURLWithPath: originalBase + suffix)
            } else {
                item = rawItem
            }
            var itemIsDir: ObjCBool = false
            fm.fileExists(atPath: rawItem.path, isDirectory: &itemIsDir)

            if itemIsDir.boolValue {
                let skillFile = item.appendingPathComponent("SKILL.md")
                let agentsFile = item.appendingPathComponent("AGENTS.md")
                let rawSkillFile = rawItem.appendingPathComponent("SKILL.md")
                let rawAgentsFile = rawItem.appendingPathComponent("AGENTS.md")

                if fm.fileExists(atPath: rawSkillFile.path) {
                    if let data = collectSkillData(at: skillFile, toolSource: toolSource, isDirectory: true, isGlobal: isGlobal, kind: kind) {
                        results.append(data)
                    }
                } else if fm.fileExists(atPath: rawAgentsFile.path) {
                    if let data = collectSkillData(at: agentsFile, toolSource: toolSource, isDirectory: true, isGlobal: isGlobal, kind: kind) {
                        results.append(data)
                    }
                } else if kind == .agent, let agentFile = preferredAgentFile(in: rawItem) {
                    let remappedAgentFile = item.appendingPathComponent(agentFile.lastPathComponent)
                    if let data = collectSkillData(at: remappedAgentFile, toolSource: toolSource, isDirectory: true, isGlobal: isGlobal, kind: kind) {
                        results.append(data)
                    }
                }
            } else if item.pathExtension == "md" || item.pathExtension == "mdc" || item.pathExtension == "toml" {
                guard !shouldIgnoreLooseMarkdownFile(named: item.lastPathComponent) else { continue }
                if let data = collectSkillData(at: item, toolSource: toolSource, isDirectory: false, isGlobal: isGlobal, kind: kind) {
                    results.append(data)
                }
            }
        }
    }

    private static func preferredAgentFile(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = contents.filter { item in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            guard !isDir.boolValue else { return false }
            guard ["md", "mdc", "toml"].contains(item.pathExtension) else { return false }
            return !shouldIgnoreLooseMarkdownFile(named: item.lastPathComponent)
        }

        let directoryName = directory.lastPathComponent.lowercased()
        if let matchingFile = candidates.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == directoryName }) {
            return matchingFile
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        return nil
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
    private static func collectSkillData(at fileURL: URL, toolSource: ToolSource, isDirectory: Bool, isGlobal: Bool, kind: ItemKind = .skill) -> ScannedSkillData? {
        let fm = FileManager.default
        let resolved = canonicalResolvedPath(for: fileURL, toolSource: toolSource)

        // Resolve symlinks for the actual read — fileURL may be a remapped canonical path
        // that does not physically exist when a parent directory is a symlink.
        let physicalURL = fileURL.resolvingSymlinksInPath()

        let parsedContent: String
        let parsedFrontmatter: [String: String]
        let parsedDescription: String
        let parsedName: String

        if kind == .note {
            guard let content = try? String(contentsOf: physicalURL, encoding: .utf8) else {
                AppLogger.scanning.warning("Failed to read note: \(fileURL.path)")
                return nil
            }
            let metadata = NotesService.metadata(for: content)
            parsedContent = content
            parsedFrontmatter = [:]
            parsedDescription = metadata.excerpt
            parsedName = metadata.title
        } else {
            guard let parsed = SkillParser.parse(fileURL: physicalURL, toolSource: toolSource) else {
                AppLogger.scanning.warning("Failed to parse: \(fileURL.path)")
                return nil
            }
            parsedContent = parsed.content
            parsedFrontmatter = parsed.frontmatter
            parsedDescription = parsed.description
            parsedName = parsed.name
        }

        let attrs = try? fm.attributesOfItem(atPath: physicalURL.path)
        let modDate  = (attrs?[.modificationDate] as? Date) ?? .now
        let fileSize = (attrs?[.size] as? Int) ?? 0

        let name: String
        if !parsedName.isEmpty {
            name = parsedName
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
            skillDescription: parsedDescription,
            content: parsedContent,
            frontmatter: parsedFrontmatter,
            modDate: modDate,
            fileSize: fileSize,
            kind: kind
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
                existing.itemKind = preferredData.kind
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
                    resolvedPath: primary.resolvedPath,
                    kind: primary.kind
                )
                skill.installedPaths = installedPaths
                skill.toolSources = toolSources
                modelContext.insert(skill)
            }
        }

        for skill in localSkills where !scannedResolvedPaths.contains(skill.resolvedPath) {
            modelContext.delete(skill)
        }

        do { try modelContext.save() } catch {
            AppLogger.scanning.error("SwiftData save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Remote Server Scanning

    @MainActor
    func syncAllRemoteServers() async {
        let descriptor = FetchDescriptor<RemoteServer>()
        guard let servers = try? modelContext.fetch(descriptor) else { return }
        for server in servers {
            await scanRemoteServer(server)
        }
    }

    /// Scans a remote server for skills. Sets lastSyncError on failure.
    @MainActor
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
                    if let fileIndex = components.lastIndex(of: "SKILL.md"), fileIndex > 0 {
                        name = components[fileIndex - 1]
                    } else {
                        name = "Unknown"
                    }
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
            do { try modelContext.save() } catch {
                AppLogger.scanning.error("SwiftData save failed after sync: \(error.localizedDescription)")
            }
        } catch {
            server.lastSyncError = error.localizedDescription
            do { try modelContext.save() } catch {
                AppLogger.scanning.error("SwiftData save failed after sync error: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
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
        do { try modelContext.save() } catch {
            AppLogger.scanning.error("SwiftData save failed: \(error.localizedDescription)")
        }
    }

    deinit {
        scanTask?.cancel()
    }
}
