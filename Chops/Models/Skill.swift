import SwiftData
import Foundation

enum SkillCategory: String, CaseIterable, Hashable {
    case skill = "skill"
    case agents = "agents"
    case rules = "rules"

    var displayName: String {
        switch self {
        case .skill: "Skills"
        case .agents: "Agents"
        case .rules: "Rules"
        }
    }

    var icon: String {
        switch self {
        case .skill: "doc.text.fill"
        case .agents: "person.2.fill"
        case .rules: "list.bullet.rectangle.fill"
        }
    }
}

// MARK: - Schema Migration Notes
// Properties added in v1.1:
// - isBase: Bool = false — marks skill as a base/template skill
// - categoryRaw: String = "skill" — skill category (skill, agents, rules)
// - linkedToolsRaw: String = "" — comma-separated tools linked via symlink
// All have default values, enabling SwiftData lightweight migration.
// If breaking changes occur, implement VersionedSchema per:
// https://developer.apple.com/documentation/swiftdata/migratingyourappstonewermodelversions

@Model
final class Skill {
    @Attribute(.unique) var resolvedPath: String
    var filePath: String
    var isDirectory: Bool
    var name: String
    var skillDescription: String
    var content: String
    var frontmatterData: Data?

    var collections: [SkillCollection]
    var isFavorite: Bool
    var lastOpened: Date?
    var fileModifiedDate: Date
    var fileSize: Int
    var isGlobal: Bool
    var isBase: Bool = false
    var categoryRaw: String = "skill"
    /// Comma-separated tool raw values for tools linked via symlink (e.g. "cursor,windsurf")
    var linkedToolsRaw: String = ""

    var remoteServer: RemoteServer?
    var remotePath: String?

    var isRemote: Bool { remoteServer != nil }

    /// Comma-separated tool raw values (e.g. "claude,cursor,codex")
    var toolSourcesRaw: String

    /// All file paths where this skill is installed (JSON-encoded array)
    var installedPathsData: Data?

    // MARK: - Computed

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
            installedPathsData = try? JSONEncoder().encode(Array(Set(newValue)))
        }
    }

    var frontmatter: [String: String] {
        get {
            guard let data = frontmatterData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            frontmatterData = try? JSONEncoder().encode(newValue)
        }
    }

    var linkedTools: [ToolSource] {
        get {
            linkedToolsRaw
                .split(separator: ",")
                .compactMap { ToolSource(rawValue: String($0)) }
        }
        set {
            let unique = Array(Set(newValue.map(\.rawValue))).sorted()
            linkedToolsRaw = unique.joined(separator: ",")
        }
    }

    /// Tools where we created a symlink that is now unresolvable.
    /// Note: This performs filesystem checks and should be cached if used frequently.
    func computeBrokenLinkedTools() -> [ToolSource] {
        linkedTools.filter { tool in
            guard let globalPath = SymlinkService.findMatchingPath(for: category, in: tool.globalPaths) else {
                return false
            }
            let sourcePath = isDirectory
                ? (filePath as NSString).deletingLastPathComponent
                : filePath
            let itemName = (sourcePath as NSString).lastPathComponent
            let linkPath = "\(globalPath)/\(itemName)"

            var s = stat()
            guard Darwin.lstat(linkPath, &s) == 0 else { return false }
            let isSymlink = (s.st_mode & S_IFMT) == S_IFLNK
            guard isSymlink else { return false }
            return !FileManager.default.fileExists(atPath: linkPath)
        }
    }

    /// Cached broken tools - use for display purposes
    var brokenLinkedTools: [ToolSource] {
        computeBrokenLinkedTools()
    }

    var category: SkillCategory {
        get { SkillCategory(rawValue: categoryRaw) ?? .skill }
        set { categoryRaw = newValue.rawValue }
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

    // MARK: - Init

    init(
        filePath: String,
        toolSource: ToolSource,
        isDirectory: Bool = false,
        name: String = "",
        skillDescription: String = "",
        content: String = "",
        frontmatter: [String: String] = [:],
        category: SkillCategory = .skill,

        collections: [SkillCollection] = [],
        isFavorite: Bool = false,
        lastOpened: Date? = nil,
        fileModifiedDate: Date = .now,
        fileSize: Int = 0,
        isGlobal: Bool = true,
        resolvedPath: String = ""
    ) {
        self.resolvedPath = resolvedPath.isEmpty ? filePath : resolvedPath
        self.filePath = filePath
        self.toolSourcesRaw = toolSource.rawValue
        self.installedPathsData = try? JSONEncoder().encode([filePath])
        self.isDirectory = isDirectory
        self.name = name
        self.skillDescription = skillDescription
        self.content = content
        self.frontmatterData = try? JSONEncoder().encode(frontmatter)
        self.categoryRaw = category.rawValue

        self.collections = collections
        self.isFavorite = isFavorite
        self.lastOpened = lastOpened
        self.fileModifiedDate = fileModifiedDate
        self.fileSize = fileSize
        self.isGlobal = isGlobal
    }

    // MARK: - Merge

    func addSymlinkTarget(_ tool: ToolSource) {
        var tools = linkedTools
        if !tools.contains(tool) {
            tools.append(tool)
            linkedTools = tools
        }
    }

    func removeSymlinkTarget(_ tool: ToolSource) {
        var tools = linkedTools
        tools.removeAll { $0 == tool }
        linkedTools = tools

        // Also remove from toolSources if it was only linked (not native)
        var sources = toolSources
        if sources.contains(tool) && !installedPaths.contains(where: { path in
            tool.globalPaths.contains { globalPath in
                path.hasPrefix(globalPath)
            }
        }) {
            sources.removeAll { $0 == tool }
            toolSources = sources
        }
    }

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

    var deletionTargets: [String] {
        Array(
            Set(
                ([filePath] + installedPaths).map { path in
                    if isDirectory {
                        return (path as NSString).deletingLastPathComponent
                    }
                    return path
                }
            )
        ).sorted()
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
