import SwiftData
import Foundation

enum ItemKind: String, Codable, CaseIterable {
    case skill
    case agent
    case rule

    var displayName: String {
        switch self {
        case .skill: "Skills"
        case .agent: "Agents"
        case .rule: "Rules"
        }
    }

    var singularName: String {
        switch self {
        case .skill: "Skill"
        case .agent: "Agent"
        case .rule: "Rule"
        }
    }

    var icon: String {
        switch self {
        case .skill: "doc.text"
        case .agent: "person.crop.rectangle"
        case .rule: "list.bullet.rectangle"
        }
    }
}

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

    var remoteServer: RemoteServer?
    var remotePath: String?

    var isRemote: Bool { remoteServer != nil }

    var isPlugin: Bool {
        filePath.contains("/.claude/plugins/") ||
        filePath.contains("/local-agent-mode-sessions/") ||
        toolSources.contains(.claudeDesktop)
    }

    var isReadOnly: Bool {
        isPlugin || isBundledOpenClawSkill
    }

    /// Comma-separated tool raw values (e.g. "claude,cursor,codex")
    var toolSourcesRaw: String

    /// All file paths where this skill is installed (JSON-encoded array)
    var installedPathsData: Data?

    /// Raw `ItemKind` value. Defaults to `"skill"` for lightweight migration compatibility.
    var kind: String = ItemKind.skill.rawValue

    // MARK: - Computed

    var itemKind: ItemKind {
        get { ItemKind(rawValue: kind) ?? .skill }
        set { kind = newValue.rawValue }
    }

    var displayTypeName: String {
        switch itemKind {
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

    // MARK: - Init

    init(
        filePath: String,
        toolSource: ToolSource,
        isDirectory: Bool = false,
        name: String = "",
        skillDescription: String = "",
        content: String = "",
        frontmatter: [String: String] = [:],

        collections: [SkillCollection] = [],
        isFavorite: Bool = false,
        lastOpened: Date? = nil,
        fileModifiedDate: Date = .now,
        fileSize: Int = 0,
        isGlobal: Bool = true,
        resolvedPath: String = "",
        kind: ItemKind = .skill
    ) {
        self.resolvedPath = resolvedPath.isEmpty ? filePath : resolvedPath
        self.filePath = filePath
        self.toolSourcesRaw = toolSource.rawValue
        self.installedPathsData = try? JSONEncoder().encode([filePath]) // [String] encode never throws
        self.isDirectory = isDirectory
        self.name = name
        self.skillDescription = skillDescription
        self.content = content
        self.frontmatterData = try? JSONEncoder().encode(frontmatter) // [String: String] encode never throws

        self.collections = collections
        self.isFavorite = isFavorite
        self.lastOpened = lastOpened
        self.fileModifiedDate = fileModifiedDate
        self.fileSize = fileSize
        self.isGlobal = isGlobal
        self.kind = kind.rawValue
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
