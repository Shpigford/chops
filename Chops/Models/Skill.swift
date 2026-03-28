import SwiftData
import Foundation

enum ItemKind: String, Codable, CaseIterable {
    case skill
    case agent
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

    /// Comma-separated tool raw values (e.g. "claude,cursor,codex")
    var toolSourcesRaw: String

    /// All file paths where this skill is installed (JSON-encoded array)
    var installedPathsData: Data?

    /// Discriminator: "skill" or "agent"
    var kind: String = ItemKind.skill.rawValue

    // MARK: - Computed

    var itemKind: ItemKind {
        get { ItemKind(rawValue: kind) ?? .skill }
        set { kind = newValue.rawValue }
    }

    var displayTypeName: String {
        itemKind == .agent ? "Agent" : "Skill"
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

    /// How many tools this skill is installed for
    var installCount: Int { toolSources.count }

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
        self.installedPathsData = try? JSONEncoder().encode([filePath])
        self.isDirectory = isDirectory
        self.name = name
        self.skillDescription = skillDescription
        self.content = content
        self.frontmatterData = try? JSONEncoder().encode(frontmatter)

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

    /// Copy this skill to another tool's skill directory
    func copyToTool(_ targetTool: ToolSource) throws {
        let fm = FileManager.default

        // Get the source path (prefer the original filePath)
        let sourcePath = filePath
        guard fm.fileExists(atPath: sourcePath) else {
            throw SkillCopyError.sourceNotFound(sourcePath)
        }

        // Get target tool's skill directory
        guard let targetDir = targetTool.globalPaths.first else {
            throw SkillCopyError.targetToolHasNoPath(targetTool.displayName)
        }

        // Create target directory if it doesn't exist
        try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        // Determine source and destination
        let sourceFolderPath: String
        let destinationPath: String

        if isDirectory {
            // If source is a directory, copy the folder directly
            sourceFolderPath = sourcePath
            destinationPath = (targetDir as NSString).appendingPathComponent((sourcePath as NSString).lastPathComponent)
        } else {
            // If source is a file, copy its containing folder
            sourceFolderPath = (sourcePath as NSString).deletingLastPathComponent
            destinationPath = (targetDir as NSString).appendingPathComponent((sourceFolderPath as NSString).lastPathComponent)
        }

        // Don't copy if already exists at destination
        if fm.fileExists(atPath: destinationPath) {
            throw SkillCopyError.alreadyExists(destinationPath)
        }

        // Copy the folder
        try fm.copyItem(atPath: sourceFolderPath, toPath: destinationPath)

        // Determine the actual copied file path
        let copiedFilePath: String
        if isDirectory {
            copiedFilePath = destinationPath
        } else {
            copiedFilePath = (destinationPath as NSString).appendingPathComponent((sourcePath as NSString).lastPathComponent)
        }

        // Update this skill's metadata to track the new installation
        addInstallation(path: copiedFilePath, tool: targetTool)
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

enum SkillCopyError: LocalizedError {
    case sourceNotFound(String)
    case targetToolHasNoPath(String)
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path):
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let displayPath = path.replacingOccurrences(of: home, with: "~")
            return "Source skill not found at \(displayPath)."
        case .targetToolHasNoPath(let toolName):
            return "\(toolName) doesn't have a configured skills directory."
        case .alreadyExists(let path):
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let displayPath = path.replacingOccurrences(of: home, with: "~")
            return "This skill is already installed at \(displayPath)."
        }
    }
}
