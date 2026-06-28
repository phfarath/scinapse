// SciNapseKit/Sources/SciNapseKit/Verification/Types.swift
import Foundation

public struct ResolvedMetadata: Sendable, Equatable {
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
    public var doi: String?
    public var pmid: String?

    public init(title: String? = nil, authors: [String] = [], journal: String? = nil,
                year: Int? = nil, month: String? = nil, day: Int? = nil,
                volume: String? = nil, issue: String? = nil, pages: String? = nil,
                abstract: String? = nil, workType: String? = nil,
                doi: String? = nil, pmid: String? = nil) {
        self.title = title; self.authors = authors; self.journal = journal
        self.year = year; self.month = month; self.day = day
        self.volume = volume; self.issue = issue; self.pages = pages
        self.abstract = abstract; self.workType = workType; self.doi = doi; self.pmid = pmid
    }
}

public struct RetractionInfo: Sendable, Equatable {
    public var status: RetractionStatus
    public var date: Date?
    public var noticeDOI: String?
    public init(status: RetractionStatus, date: Date? = nil, noticeDOI: String? = nil) {
        self.status = status; self.date = date; self.noticeDOI = noticeDOI
    }
    public static let none = RetractionInfo(status: .none)
}

public struct OpenAccessInfo: Sendable, Equatable {
    public var isOpenAccess: Bool
    public var status: String?
    public var url: String?
    public init(isOpenAccess: Bool, status: String? = nil, url: String? = nil) {
        self.isOpenAccess = isOpenAccess; self.status = status; self.url = url
    }
    public static let unknown = OpenAccessInfo(isOpenAccess: false)
}

public enum ParsedIdentifier: Sendable, Equatable {
    case doi(String)
    case pmid(String)
    case url(URL)
    case unknown
}

public struct VerificationResult: Sendable, Equatable {
    public var metadata: ResolvedMetadata
    public var trustTier: TrustTier
    public var retraction: RetractionInfo
    public var openAccess: OpenAccessInfo
    public var resolvedURL: String?
    public init(metadata: ResolvedMetadata, trustTier: TrustTier,
                retraction: RetractionInfo = .none, openAccess: OpenAccessInfo = .unknown,
                resolvedURL: String? = nil) {
        self.metadata = metadata; self.trustTier = trustTier
        self.retraction = retraction; self.openAccess = openAccess; self.resolvedURL = resolvedURL
    }
}

public protocol MetadataResolving: Sendable {
    func verify(_ raw: String) async throws -> VerificationResult
}
