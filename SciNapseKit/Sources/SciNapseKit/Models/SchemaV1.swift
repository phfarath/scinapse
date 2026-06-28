// SciNapseKit/Sources/SciNapseKit/Models/SchemaV1.swift
import Foundation
import SwiftData

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Topic.self, Post.self, Source.self]
    }
}

public enum AppMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
