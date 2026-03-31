import Foundation
import SwiftData

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

typealias Skill = SchemaV1.Skill
typealias SkillCollection = SchemaV1.SkillCollection
typealias RemoteServer = SchemaV1.RemoteServer

enum ChopsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
