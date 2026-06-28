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
            apply(r, to: source)
            source.verificationState = .completed
        } catch AppError.offline {
            source.trustTier = .unverified
            source.verificationState = .pending
        } catch {
            source.trustTier = .unverified
            source.verificationState = .failed
        }
        source.updatedAt = Date()
    }

    private func apply(_ r: VerificationResult, to s: Source) {
        let m = r.metadata
        s.normalizedDOI = m.doi
        s.pmid = m.pmid
        s.resolvedURL = r.resolvedURL
        s.title = m.title
        s.authors = m.authors
        s.journal = m.journal
        s.year = m.year
        s.month = m.month
        s.day = m.day
        s.volume = m.volume
        s.issue = m.issue
        s.pages = m.pages
        s.abstract = m.abstract
        s.workType = m.workType
        s.trustTier = r.trustTier
        s.retractionStatus = r.retraction.status
        s.retractionDate = r.retraction.date
        s.retractionNoticeDOI = r.retraction.noticeDOI
        s.isOpenAccess = r.openAccess.isOpenAccess
        s.oaStatus = r.openAccess.status
        s.oaURL = r.openAccess.url
        s.fetchedAt = Date()
        // Citação Vancouver só quando há metadados suficientes
        if m.title != nil || !m.authors.isEmpty {
            s.formattedCitation = VancouverFormatter.format(m)
        }
    }
}
