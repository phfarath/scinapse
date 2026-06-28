// SciNapseKit/Sources/SciNapseKit/Verification/PubMedClient.swift
import Foundation

public struct PubMedClient: Sendable {
    private let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    private var qs: String { "tool=\(Config.pubmedTool)&email=\(Config.contactEmail)" }

    // MARK: PMID -> DOI via PMC ID Converter
    private struct ConverterResponse: Decodable { let records: [Record]? }
    private struct Record: Decodable { let pmid: String?; let doi: String? }

    public func resolveDOI(pmid: String) async -> String? {
        let urlStr = "https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/?ids=\(pmid)&idtype=pmid&format=json&\(qs)"
        guard let url = URL(string: urlStr),
              let resp = try? await http.get(url, headers: [:]), resp.status == 200,
              let decoded = try? JSONDecoder().decode(ConverterResponse.self, from: resp.data) else { return nil }
        return decoded.records?.first?.doi
    }

    // MARK: ESummary (JSON) -> metadados
    public func fetchSummary(pmid: String) async throws -> ResolvedMetadata {
        let urlStr = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=\(pmid)&retmode=json&\(qs)"
        guard let url = URL(string: urlStr) else { throw AppError.unresolvable }
        let resp = try await http.get(url, headers: [:])
        guard resp.status == 200 else { throw AppError.invalidResponse }

        // result é um dicionário com a chave do PMID + "uids"; decodificamos manualmente.
        guard let root = try JSONSerialization.jsonObject(with: resp.data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let entry = result[pmid] as? [String: Any] else {
            throw AppError.notFound
        }
        var meta = ResolvedMetadata()
        meta.pmid = pmid
        meta.title = entry["title"] as? String
        meta.journal = entry["fulljournalname"] as? String
        meta.volume = entry["volume"] as? String
        meta.issue = entry["issue"] as? String
        meta.pages = entry["pages"] as? String
        if let pubdate = entry["pubdate"] as? String,
           let yearStr = pubdate.split(separator: " ").first, let y = Int(yearStr) {
            meta.year = y
        }
        if let authors = entry["authors"] as? [[String: Any]] {
            meta.authors = authors.compactMap { $0["name"] as? String }
        }
        if let ids = entry["articleids"] as? [[String: Any]] {
            meta.doi = ids.first(where: { ($0["idtype"] as? String) == "doi" })?["value"] as? String
        }
        return meta
    }
}
