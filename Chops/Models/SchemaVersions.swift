import Foundation
import SwiftData

// MARK: - v1.0.0 — Original schema (Skill, SkillCollection, RemoteServer)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Skill.self, SkillCollection.self, RemoteServer.self]
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

        var toolSourcesRaw: String
        var installedPathsData: Data?
        var kind: String = ItemKind.skill.rawValue

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
    }

    @Model
    final class SkillCollection {
        @Attribute(.unique) var name: String
        var icon: String
        var sortOrder: Int

        @Relationship(inverse: \Skill.collections)
        var skills: [Skill]

        init(name: String, icon: String = "folder", skills: [Skill] = [], sortOrder: Int = 0) {
            self.name = name
            self.icon = icon
            self.skills = skills
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class RemoteServer {
        @Attribute(.unique) var id: String
        var label: String
        var host: String
        var port: Int
        var username: String
        var skillsBasePath: String
        var sshKeyPath: String?
        var lastSyncDate: Date?
        var lastSyncError: String?

        @Relationship(deleteRule: .cascade, inverse: \Skill.remoteServer)
        var skills: [Skill]

        init(
            label: String,
            host: String,
            port: Int = 22,
            username: String,
            skillsBasePath: String
        ) {
            self.id = UUID().uuidString
            self.label = label
            self.host = host
            self.port = port
            self.username = username
            self.skillsBasePath = skillsBasePath
            self.skills = []
        }
    }
}

// MARK: - v1.1.0 — Adds SymlinkTarget for multi-vendor symlink tracking

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [Skill.self, SkillCollection.self, RemoteServer.self, SymlinkTarget.self]
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

        var toolSourcesRaw: String
        var installedPathsData: Data?
        var kind: String = ItemKind.skill.rawValue

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
    }

    @Model
    final class SkillCollection {
        @Attribute(.unique) var name: String
        var icon: String
        var sortOrder: Int

        @Relationship(inverse: \Skill.collections)
        var skills: [Skill]

        init(name: String, icon: String = "folder", skills: [Skill] = [], sortOrder: Int = 0) {
            self.name = name
            self.icon = icon
            self.skills = skills
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class RemoteServer {
        @Attribute(.unique) var id: String
        var label: String
        var host: String
        var port: Int
        var username: String
        var skillsBasePath: String
        var sshKeyPath: String?
        var lastSyncDate: Date?
        var lastSyncError: String?

        @Relationship(deleteRule: .cascade, inverse: \Skill.remoteServer)
        var skills: [Skill]

        init(
            label: String,
            host: String,
            port: Int = 22,
            username: String,
            skillsBasePath: String
        ) {
            self.id = UUID().uuidString
            self.label = label
            self.host = host
            self.port = port
            self.username = username
            self.skillsBasePath = skillsBasePath
            self.skills = []
        }
    }

    @Model
    final class SymlinkTarget {
        @Attribute(.unique) var id: String
        var skillResolvedPath: String
        // Stored as raw String so #Predicate can filter without a computed property.
        var toolSource: String
        var linkedPath: String
        var kind: String
        var isBroken: Bool = false

        init(skillResolvedPath: String, toolSource: ToolSource, linkedPath: String, kind: ItemKind) {
            self.id = "\(skillResolvedPath)\n\(toolSource.rawValue)"
            self.skillResolvedPath = skillResolvedPath
            self.toolSource = toolSource.rawValue
            self.linkedPath = linkedPath
            self.kind = kind.rawValue
        }
    }
}

// MARK: - Typealiases (always point to the latest schema)

typealias Skill = SchemaV2.Skill
typealias SkillCollection = SchemaV2.SkillCollection
typealias RemoteServer = SchemaV2.RemoteServer
typealias SymlinkTarget = SchemaV2.SymlinkTarget

// MARK: - Migration plan

enum ChopsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
