// SciNapseKit/Sources/SciNapseKit/Models/Source.swift
import Foundation
import SwiftData

@Model
public final class Source {
    @Attribute(.unique) public var id: UUID
    public var rawInput: String
    public var kind: SourceKind
    public var normalizedDOI: String?
    public var pmid: String?
    public var resolvedURL: String?

    public var title: String?
    public var authors: [String]
    public var journal: String?
    public var year: Int?
    public var month: String?
    public var day: Int?
    public var volume: String?
    public var issue: String?
    public var pages: String?
    public var abstract: String?
    public var workType: String?

    public var trustTier: TrustTier
    public var verificationState: VerificationState
    public var retractionStatus: RetractionStatus
    public var retractionDate: Date?
    public var retractionNoticeDOI: String?

    public var isOpenAccess: Bool
    public var oaStatus: String?
    public var oaURL: String?

    public var formattedCitation: String?
    public var savedStandalone: Bool
    public var topic: Topic?

    public var createdAt: Date
    public var updatedAt: Date
    public var fetchedAt: Date?
    public var remoteID: String?
    public var syncStatus: SyncStatus

    // Lado inverso do N↔N — SEM @Relationship (declarado em Post.sources)
    public var posts: [Post] = []

    public init(rawInput: String, kind: SourceKind) {
        self.id = UUID()
        self.rawInput = rawInput
        self.kind = kind
        self.authors = []
        self.trustTier = .unverified
        self.verificationState = .pending
        self.retractionStatus = .none
        self.isOpenAccess = false
        self.savedStandalone = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.remoteID = nil
        self.syncStatus = .pending
    }
}
