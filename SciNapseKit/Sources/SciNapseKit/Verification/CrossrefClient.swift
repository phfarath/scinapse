// SciNapseKit/Sources/SciNapseKit/Verification/CrossrefClient.swift
import Foundation

public struct CrossrefClient: Sendable {
    private let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    private struct Envelope: Decodable { let message: Message }
    private struct Message: Decodable {
        let DOI: String?
        let title: [String]?
        let containerTitle: [String]?
        let type: String?
        let volume: String?
        let issue: String?
        let page: String?
        let abstract: String?
        let author: [Author]?
        let issued: DateParts?
        let publishedPrint: DateParts?
        let publishedOnline: DateParts?
        let updatedBy: [Update]?
        enum CodingKeys: String, CodingKey {
            case DOI, title, type, volume, issue, page, abstract, author, issued
            case containerTitle = "container-title"
            case publishedPrint = "published-print"
            case publishedOnline = "published-online"
            case updatedBy = "updated-by"
        }
    }
    private struct Author: Decodable { let given: String?; let family: String? }
    private struct DateParts: Decodable { let dateParts: [[Int]]?; enum CodingKeys: String, CodingKey { case dateParts = "date-parts" } }
    private struct Update: Decodable { let DOI: String?; let type: String?; let updated: DateParts? }

    public func fetch(doi: String) async throws -> (ResolvedMetadata, RetractionInfo) {
        guard let url = URL(string: "https://api.crossref.org/v1/works/\(doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi)") else { throw AppError.invalidResponse }
        let resp = try await http.get(url, headers: ["User-Agent": Config.userAgent])
        guard resp.status != 404 else { throw AppError.notFound }
        guard resp.status == 200 else { throw AppError.invalidResponse }
        let decoder = JSONDecoder()
        let msg = try decoder.decode(Envelope.self, from: resp.data).message

        var meta = ResolvedMetadata()
        meta.doi = msg.DOI
        meta.title = msg.title?.first.map(stripRetractedPrefix)
        meta.journal = msg.containerTitle?.first
        meta.workType = msg.type
        meta.volume = msg.volume
        meta.issue = msg.issue
        meta.pages = msg.page
        meta.abstract = msg.abstract.map(stripJATS)
        meta.authors = (msg.author ?? []).compactMap(formatAuthor)
        let dp = (msg.issued ?? msg.publishedPrint ?? msg.publishedOnline)?.dateParts?.first
        meta.year = dp?.first
        if let dp, dp.count > 1 { meta.month = monthAbbrev(dp[1]) }
        if let dp, dp.count > 2 { meta.day = dp[2] }

        let retraction = parseRetraction(msg.updatedBy, titleHadPrefix: msg.title?.first?.uppercased().hasPrefix("RETRACTED:") ?? false)
        return (meta, retraction)
    }

    private func formatAuthor(_ a: Author) -> String? {
        guard let family = a.family else { return a.given }
        let initials = (a.given ?? "")
            .components(separatedBy: CharacterSet(charactersIn: " .-"))
            .compactMap { $0.first.map(String.init) }
            .prefix(2)
            .joined()
        return initials.isEmpty ? family : "\(family) \(initials)"
    }

    private func parseRetraction(_ updates: [Update]?, titleHadPrefix: Bool) -> RetractionInfo {
        guard let updates, !updates.isEmpty else {
            return titleHadPrefix ? RetractionInfo(status: .retracted) : .none
        }
        // Prioridade: retraction > concern > correction. Duplicatas (mesmo aviso, fontes publisher+retraction-watch) colapsam via first-match por tipo.
        func date(_ u: Update) -> Date? {
            guard let y = u.updated?.dateParts?.first?.first else { return nil }
            return Calendar(identifier: .gregorian).date(from: DateComponents(year: y))
        }
        if let u = updates.first(where: { $0.type == "retraction" }) {
            return RetractionInfo(status: .retracted, date: date(u), noticeDOI: u.DOI)
        }
        if let u = updates.first(where: { $0.type == "expression_of_concern" }) {
            return RetractionInfo(status: .concern, date: date(u), noticeDOI: u.DOI)
        }
        if let u = updates.first(where: { $0.type == "correction" }) {
            return RetractionInfo(status: .correction, date: date(u), noticeDOI: u.DOI)
        }
        return .none
    }

    private func stripRetractedPrefix(_ t: String) -> String {
        let upper = t.uppercased()
        if upper.hasPrefix("RETRACTED:") { return String(t.dropFirst("RETRACTED:".count)).trimmingCharacters(in: .whitespaces) }
        return t
    }
    private func stripJATS(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func monthAbbrev(_ m: Int) -> String? {
        let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return (1...12).contains(m) ? names[m-1] : nil
    }
}
