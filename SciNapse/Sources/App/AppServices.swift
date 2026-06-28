// SciNapse/Sources/App/AppServices.swift
import Foundation
import SwiftData
import SciNapseKit

@MainActor
final class AppServices: ObservableObject {
    let container: ModelContainer
    let resolver: any MetadataResolving

    init(container: ModelContainer, resolver: any MetadataResolving) {
        self.container = container
        self.resolver = resolver
    }

    func addSource(rawInput: String, topicID: PersistentIdentifier?, postID: PersistentIdentifier?, savedStandalone: Bool) async -> PersistentIdentifier {
        let fetcher = SourceFetcher(modelContainer: container)
        return await fetcher.addSource(rawInput: rawInput, topicID: topicID, postID: postID, savedStandalone: savedStandalone, using: resolver)
    }

    func reverify(_ id: PersistentIdentifier) async {
        let fetcher = SourceFetcher(modelContainer: container)
        await fetcher.reverify(sourceID: id, using: resolver)
    }
}
