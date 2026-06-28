// SciNapseKit/Sources/SciNapseKit/Persistence/ModelContainerFactory.swift
import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: config)
    }
}
