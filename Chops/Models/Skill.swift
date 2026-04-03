import SwiftData
import Foundation

enum ItemKind: String, Codable, CaseIterable {
    case note
    case skill
    case agent
    case rule

    var displayName: String {
        switch self {
        case .note: "Notes"
        case .skill: "Skills"
        case .agent: "Agents"
        case .rule: "Rules"
        }
    }

    var singularName: String {
        switch self {
        case .note: "Note"
        case .skill: "Skill"
        case .agent: "Agent"
        case .rule: "Rule"
        }
    }

    var icon: String {
        switch self {
        case .note: "note.text"
        case .skill: "doc.text"
        case .agent: "person.crop.rectangle"
        case .rule: "list.bullet.rectangle"
        }
    }
}

extension Skill {
    var isRemote: Bool { remoteServer != nil }

    var isPlugin: Bool {
        filePath.contains("/.claude/plugins/") ||
        filePath.contains("/local-agent-mode-sessions/") ||
        toolSources.contains(.claudeDesktop)
    }

    var isReadOnly: Bool {
        isPlugin || isBundledOpenClawSkill
    }

    // MARK: - Computed

    var itemKind: ItemKind {
        get { ItemKind(rawValue: kind) ?? .skill }
        set { kind = newValue.rawValue }
    }

    var displayTypeName: String {
        switch itemKind {
        case .note: "Note"
        case .agent: "Agent"
        case .rule: "Rule"
        case .skill: "Skill"
        }
    }

    var toolSources: [ToolSource] {
        get {
            toolSourcesRaw
                .split(separator: ",")
                .compactMap { ToolSource(rawValue: String($0)) }
        }
        set {
            let unique = Array(Set(newValue.map(\.rawValue))).sorted()
            toolSourcesRaw = unique.joined(separator: ",")
        }
    }

    /// Primary tool source (first one added)
    var toolSource: ToolSource {
        toolSources.first ?? .custom
    }

    var installedPaths: [String] {
        get {
            guard let data = installedPathsData else { return [filePath] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? [filePath]
        }
        set {
            do {
                installedPathsData = try JSONEncoder().encode(Array(Set(newValue)))
            } catch {
                AppLogger.fileIO.fault("Failed to encode installedPaths: \(error.localizedDescription)")
            }
        }
    }

    var frontmatter: [String: String] {
        get {
            guard let data = frontmatterData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            do {
                frontmatterData = try JSONEncoder().encode(newValue)
            } catch {
                AppLogger.fileIO.fault("Failed to encode frontmatter: \(error.localizedDescription)")
            }
        }
    }

    /// How many tools this skill is installed for
    var installCount: Int { toolSources.count }

    private var isBundledOpenClawSkill: Bool {
        filePath.hasPrefix("/opt/homebrew/lib/node_modules/openclaw/skills/")
            || filePath.hasPrefix("/usr/local/lib/node_modules/openclaw/skills/")
    }

    /// For project-level skills, extracts the project name from the path.
    /// e.g. ~/Development/every-expert/.claude/skills/foo/SKILL.md → "every-expert"
    var projectName: String? {
        guard !isGlobal else { return nil }
        let components = filePath.components(separatedBy: "/")
        // Find the component before a dotfile directory (.claude, .cursor, .codex, etc.)
        for (i, component) in components.enumerated() {
            if component.hasPrefix(".") && i > 0 {
                return components[i - 1]
            }
        }
        return nil
    }

    // MARK: - Merge

    /// Merge another location/tool into this skill
    func addInstallation(path: String, tool: ToolSource) {
        var paths = installedPaths
        if !paths.contains(path) {
            paths.append(path)
            installedPaths = paths
        }
        var tools = toolSources
        if !tools.contains(tool) {
            tools.append(tool)
            toolSources = tools
        }
    }

    private var linkedAgentSkillDirectories: [String] {
        guard isDirectory else { return [] }

        let fm = FileManager.default
        let skillDirectoryName = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .lastPathComponent

        guard !skillDirectoryName.isEmpty else { return [] }

        let canonicalDirectories = Set(
            ([filePath] + installedPaths).map {
                URL(fileURLWithPath: $0)
                    .deletingLastPathComponent()
                    .resolvingSymlinksInPath()
                    .path
            }
        )

        return AgentTarget.all.compactMap { agent in
            let candidate = "\(agent.expandedSkillsDir)/\(skillDirectoryName)"
            guard fm.fileExists(atPath: candidate) else { return nil }
            let resolvedCandidate = URL(fileURLWithPath: candidate)
                .resolvingSymlinksInPath()
                .path
            return canonicalDirectories.contains(resolvedCandidate) ? candidate : nil
        }
    }

    var deletionTargets: [String] {
        var targets = Set(
            ([filePath] + installedPaths).map { path in
                if isDirectory {
                    return (path as NSString).deletingLastPathComponent
                }
                return path
            }
        )

        targets.formUnion(linkedAgentSkillDirectories)
        return Array(targets).sorted()
    }

    var canMakeGlobal: Bool {
        itemKind == .skill
            && isDirectory
            && !isRemote
            && !isReadOnly
            && !toolSources.contains(.agents)
    }

    func makeGlobal() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let currentSkillDir = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
        let skillDirName = currentSkillDir.lastPathComponent

        let agentsSkillsDir = "\(home)/.agents/skills"
        let canonicalDir = "\(agentsSkillsDir)/\(skillDirName)"
        let canonicalFile = "\(canonicalDir)/SKILL.md"

        guard !fm.fileExists(atPath: canonicalDir) else {
            throw MakeGlobalError.alreadyExists(skillDirName)
        }

        try fm.createDirectory(atPath: agentsSkillsDir, withIntermediateDirectories: true)

        // Move original directory to canonical location
        let originalDir = currentSkillDir.path
        try fm.moveItem(atPath: originalDir, toPath: canonicalDir)

        // Replace original with symlink to canonical
        try fm.createSymbolicLink(atPath: originalDir, withDestinationPath: canonicalDir)

        // Create symlinks from all installed agents
        var newInstalledPaths = [canonicalFile, "\(originalDir)/SKILL.md"]
        var newToolSources: [ToolSource] = [.agents]

        if let originalTool = toolSources.first, originalTool != .agents {
            newToolSources.append(originalTool)
        }

        for agent in AgentTarget.installed {
            let agentDir = "\(agent.expandedSkillsDir)/\(skillDirName)"
            if !fm.fileExists(atPath: agentDir) {
                try fm.createDirectory(atPath: agent.expandedSkillsDir, withIntermediateDirectories: true)
                try fm.createSymbolicLink(atPath: agentDir, withDestinationPath: canonicalDir)
            }
            let agentFilePath = "\(agentDir)/SKILL.md"
            if !newInstalledPaths.contains(agentFilePath) {
                newInstalledPaths.append(agentFilePath)
            }
            if let toolSource = ToolSource.allCases.first(where: { $0.globalPaths.contains(agent.expandedSkillsDir) }) {
                if !newToolSources.contains(toolSource) {
                    newToolSources.append(toolSource)
                }
            }
        }

        resolvedPath = canonicalFile
        filePath = canonicalFile
        installedPaths = newInstalledPaths
        toolSources = newToolSources
        isGlobal = true
    }

    func deleteFromDisk() throws {
        let fm = FileManager.default

        for path in deletionTargets where fm.fileExists(atPath: path) {
            guard fm.isDeletableFile(atPath: path) else {
                throw SkillDeletionError.notDeletable(path)
            }
        }

        for path in deletionTargets where fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
    }
}

struct SkillTrashOperation {
    struct TrashedItem {
        let originalPath: String
        let trashedPath: String
    }

    struct SkillSnapshot {
        let resolvedPath: String
        let filePath: String
        let isDirectory: Bool
        let name: String
        let skillDescription: String
        let content: String
        let frontmatter: [String: String]
        let collectionNames: [String]
        let isFavorite: Bool
        let lastOpened: Date?
        let fileModifiedDate: Date
        let fileSize: Int
        let isGlobal: Bool
        let remoteServerID: String?
        let remotePath: String?
        let toolSources: [ToolSource]
        let installedPaths: [String]
        let kind: ItemKind

        init(skill: Skill) {
            resolvedPath = skill.resolvedPath
            filePath = skill.filePath
            isDirectory = skill.isDirectory
            name = skill.name
            skillDescription = skill.skillDescription
            content = skill.content
            frontmatter = skill.frontmatter
            collectionNames = skill.collections.map(\.name)
            isFavorite = skill.isFavorite
            lastOpened = skill.lastOpened
            fileModifiedDate = skill.fileModifiedDate
            fileSize = skill.fileSize
            isGlobal = skill.isGlobal
            remoteServerID = skill.remoteServer?.id
            remotePath = skill.remotePath
            toolSources = skill.toolSources
            installedPaths = skill.installedPaths
            kind = skill.itemKind
        }

        @MainActor
        func restore(in modelContext: ModelContext) throws -> Skill {
            let allSkills = try modelContext.fetch(FetchDescriptor<Skill>())
            let existingSkill = allSkills.first(where: { $0.resolvedPath == resolvedPath })
            let skill = existingSkill ?? Skill(
                filePath: filePath,
                toolSource: toolSources.first ?? .custom,
                isDirectory: isDirectory,
                name: name,
                skillDescription: skillDescription,
                content: content,
                frontmatter: frontmatter,
                fileModifiedDate: fileModifiedDate,
                fileSize: fileSize,
                isGlobal: isGlobal,
                resolvedPath: resolvedPath,
                kind: kind
            )

            if existingSkill == nil {
                modelContext.insert(skill)
            }

            skill.resolvedPath = resolvedPath
            skill.filePath = filePath
            skill.isDirectory = isDirectory
            skill.name = name
            skill.skillDescription = skillDescription
            skill.content = content
            skill.frontmatter = frontmatter
            skill.isFavorite = isFavorite
            skill.lastOpened = lastOpened
            skill.fileModifiedDate = fileModifiedDate
            skill.fileSize = fileSize
            skill.isGlobal = isGlobal
            skill.remotePath = remotePath
            skill.installedPaths = installedPaths
            skill.toolSources = toolSources
            skill.itemKind = kind

            if let remoteServerID {
                let remoteServers = try modelContext.fetch(FetchDescriptor<RemoteServer>())
                skill.remoteServer = remoteServers.first(where: { $0.id == remoteServerID })
            } else {
                skill.remoteServer = nil
            }

            let allCollections = try modelContext.fetch(FetchDescriptor<SkillCollection>())
            let collectionsByName = Dictionary(uniqueKeysWithValues: allCollections.map { ($0.name, $0) })
            skill.collections = collectionNames.compactMap { collectionsByName[$0] }

            return skill
        }
    }

    let snapshots: [SkillSnapshot]
    let trashedItems: [TrashedItem]

    static func trash(_ skills: [Skill]) throws -> SkillTrashOperation {
        let snapshots = skills.map(SkillSnapshot.init)
        var trashedItems: [TrashedItem] = []

        do {
            for path in deletionTargets(for: skills) where FileManager.default.fileExists(atPath: path) {
                guard FileManager.default.isDeletableFile(atPath: path) else {
                    throw SkillDeletionError.notDeletable(path)
                }
            }

            for path in deletionTargets(for: skills) where FileManager.default.fileExists(atPath: path) {
                let originalURL = URL(fileURLWithPath: path)
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: originalURL, resultingItemURL: &trashedURL)
                trashedItems.append(
                    TrashedItem(
                        originalPath: path,
                        trashedPath: (trashedURL as URL?)?.path ?? originalURL.path
                    )
                )
            }

            return SkillTrashOperation(snapshots: snapshots, trashedItems: trashedItems)
        } catch {
            try? restoreTrashedItems(trashedItems)
            throw error
        }
    }

    @MainActor
    func restore(in modelContext: ModelContext) throws -> [Skill] {
        try Self.restoreTrashedItems(trashedItems)
        return try snapshots.map { try $0.restore(in: modelContext) }
    }

    private static func deletionTargets(for skills: [Skill]) -> [String] {
        Array(Set(skills.flatMap(\.deletionTargets)))
            .sorted {
                let lhsDepth = $0.split(separator: "/").count
                let rhsDepth = $1.split(separator: "/").count
                if lhsDepth != rhsDepth {
                    return lhsDepth > rhsDepth
                }
                return $0 < $1
            }
    }

    private static func restoreTrashedItems(_ trashedItems: [TrashedItem]) throws {
        let fileManager = FileManager.default

        for item in trashedItems.sorted(by: { lhs, rhs in
            let lhsDepth = lhs.originalPath.split(separator: "/").count
            let rhsDepth = rhs.originalPath.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }
            return lhs.originalPath < rhs.originalPath
        }) where fileManager.fileExists(atPath: item.trashedPath) {
            let originalURL = URL(fileURLWithPath: item.originalPath)
            try fileManager.createDirectory(
                at: originalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try fileManager.moveItem(atPath: item.trashedPath, toPath: item.originalPath)
        }
    }
}

enum MakeGlobalError: LocalizedError {
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name):
            return "A global skill named \"\(name)\" already exists."
        }
    }
}

enum SkillDeletionError: LocalizedError {
    case notDeletable(String)

    var errorDescription: String? {
        switch self {
        case .notDeletable(let path):
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let displayPath = path.replacingOccurrences(of: home, with: "~")
            return "Couldn't delete \(displayPath). Check permissions and try again."
        }
    }
}
