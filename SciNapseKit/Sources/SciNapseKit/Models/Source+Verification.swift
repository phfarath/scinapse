import Foundation

public extension Source {
    /// Aplica um resultado de verificação (metadados + camada + retração + OA + citação Vancouver).
    func apply(_ r: VerificationResult) {
        let m = r.metadata
        normalizedDOI = m.doi
        pmid = m.pmid
        resolvedURL = r.resolvedURL
        title = m.title
        authors = m.authors
        journal = m.journal
        year = m.year
        month = m.month
        day = m.day
        volume = m.volume
        issue = m.issue
        pages = m.pages
        abstract = m.abstract
        workType = m.workType
        trustTier = r.trustTier
        retractionStatus = r.retraction.status
        retractionDate = r.retraction.date
        retractionNoticeDOI = r.retraction.noticeDOI
        isOpenAccess = r.openAccess.isOpenAccess
        oaStatus = r.openAccess.status
        oaURL = r.openAccess.url
        fetchedAt = Date()
        verificationState = .completed
        if m.title != nil || !m.authors.isEmpty { formattedCitation = VancouverFormatter.format(m) }
    }
    func markPendingOffline() { trustTier = .unverified; verificationState = .pending }
    func markFailed() { trustTier = .unverified; verificationState = .failed }
}
