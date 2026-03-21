import SwiftData
import Foundation

// MARK: - V1: Current schema (post-UI-overhaul)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Skill.self, SkillCollection.self]
    }
}

// MARK: - Migration Plan

enum ChopsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
