// SciNapseKit/Sources/SciNapseKit/Persistence/ModelContainerFactory.swift
import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static func make(inMemory: Bool = false, appGroupID: String? = nil) throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let appGroupID,
                  let url = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                    .appendingPathComponent("SciNapse.store") {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration)
    }
}
