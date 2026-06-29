// SciNapseKit/Sources/SciNapseKit/Persistence/SourceFetcher.swift
import Foundation
import SwiftData

@ModelActor
public actor SourceFetcher {
    public func addSource(rawInput: String,
                          topicID: PersistentIdentifier?,
                          postID: PersistentIdentifier?,
                          savedStandalone: Bool,
                          using service: any MetadataResolving) async -> PersistentIdentifier {
        let source = Source(rawInput: rawInput, kind: IdentifierParser.kind(for: rawInput))
        source.savedStandalone = savedStandalone
        if let topicID, let topic = self[topicID, as: Topic.self] { source.topic = topic }
        modelContext.insert(source)
        if let postID, let post = self[postID, as: Post.self] { post.sources.append(source) }

        await resolve(source: source, rawInput: rawInput, using: service)
        try? modelContext.save()
        return source.persistentModelID
    }

    public func reverify(sourceID: PersistentIdentifier, using service: any MetadataResolving) async {
        guard let source = self[sourceID, as: Source.self] else { return }
        await resolve(source: source, rawInput: source.rawInput, using: service)
        try? modelContext.save()
    }

    private func resolve(source: Source, rawInput: String, using service: any MetadataResolving) async {
        do {
            let r = try await service.verify(rawInput)
            source.apply(r)
        } catch let error as AppError where error == .offline {
            source.markPendingOffline()
        } catch {
            source.markFailed()
        }
        source.updatedAt = Date()
    }
}
