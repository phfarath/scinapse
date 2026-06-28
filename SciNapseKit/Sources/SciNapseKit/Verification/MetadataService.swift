// SciNapseKit/Sources/SciNapseKit/Verification/MetadataService.swift
import Foundation

public struct MetadataService: MetadataResolving {
    private let http: HTTPClient
    private let crossref: CrossrefClient
    private let unpaywall: UnpaywallClient
    private let pubmed: PubMedClient

    public init(http: HTTPClient = LiveHTTPClient()) {
        self.http = http
        self.crossref = CrossrefClient(http: http)
        self.unpaywall = UnpaywallClient(http: http)
        self.pubmed = PubMedClient(http: http)
    }

    public func verify(_ raw: String) async throws -> VerificationResult {
        switch IdentifierParser.parse(raw) {
        case .doi(let doi):
            return try await verifyDOI(doi, resolvedURL: "https://doi.org/\(doi)")
        case .pmid(let pmid):
            return try await verifyPMID(pmid)
        case .url(let url):
            return try await verifyURL(url)
        case .unknown:
            return VerificationResult(metadata: ResolvedMetadata(), trustTier: .unverified, resolvedURL: raw)
        }
    }

    private func verifyDOI(_ doi: String, resolvedURL: String?) async throws -> VerificationResult {
        let (meta, retraction) = try await crossref.fetch(doi: doi)
        let oa = await unpaywall.fetch(doi: doi)
        return VerificationResult(metadata: meta, trustTier: .verified, retraction: retraction,
                                  openAccess: oa, resolvedURL: resolvedURL)
    }

    private func verifyPMID(_ pmid: String) async throws -> VerificationResult {
        if let doi = await pubmed.resolveDOI(pmid: pmid) {
            return try await verifyDOI(doi, resolvedURL: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")
        }
        let meta = try await pubmed.fetchSummary(pmid: pmid)
        return VerificationResult(metadata: meta, trustTier: .verified,
                                  resolvedURL: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")
    }

    private func verifyURL(_ url: URL) async throws -> VerificationResult {
        // DOI no path?
        if let doi = IdentifierParser.extractDOI(in: url.absoluteString) {
            return try await verifyDOI(doi, resolvedURL: url.absoluteString)
        }
        // URL do PubMed?
        if let pmid = IdentifierParser.extractPMID(in: url.absoluteString) {
            return try await verifyPMID(pmid)
        }
        // Buscar HTML e procurar DOI nas meta tags
        let resp = try await http.get(url, headers: ["User-Agent": Config.userAgent])
        let finalURL = resp.finalURL ?? url
        if resp.status == 200 {
            let html = String(decoding: resp.data, as: UTF8.self)
            if let doi = HTMLDoiExtractor.extractDOI(fromHTML: html) {
                return try await verifyDOI(doi, resolvedURL: finalURL.absoluteString)
            }
            var meta = ResolvedMetadata()
            meta.title = HTMLDoiExtractor.extractTitle(fromHTML: html)
            let tier = TrustClassifier.tier(resolvedIdentifier: false, url: finalURL)
            return VerificationResult(metadata: meta, trustTier: tier, resolvedURL: finalURL.absoluteString)
        }
        let tier = TrustClassifier.tier(resolvedIdentifier: false, url: finalURL)
        return VerificationResult(metadata: ResolvedMetadata(), trustTier: tier, resolvedURL: finalURL.absoluteString)
    }
}
