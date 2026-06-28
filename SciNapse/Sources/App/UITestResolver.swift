// SciNapse/Sources/App/UITestResolver.swift
import Foundation
import SciNapseKit

/// Resolver determinístico para XCUITest (sem rede). Decide o resultado pelo conteúdo do input.
struct UITestResolver: MetadataResolving {
    func verify(_ raw: String) async throws -> VerificationResult {
        let lower = raw.lowercased()
        if lower.contains("offline") { throw AppError.offline }
        if lower.contains("retract") || raw.contains("1758835920922055") {
            let m = ResolvedMetadata(title: "Artigo Retratado", authors: ["Doe J"], journal: "J Test", year: 2020, doi: "10.1177/1758835920922055")
            return VerificationResult(metadata: m, trustTier: .verified,
                                      retraction: RetractionInfo(status: .retracted, date: nil, noticeDOI: "10.1/notice"),
                                      resolvedURL: "https://doi.org/\(m.doi!)")
        }
        if lower.contains("who.int") {
            return VerificationResult(metadata: ResolvedMetadata(title: "Página OMS"), trustTier: .recognized, resolvedURL: raw)
        }
        if lower.contains("blog") || lower.contains("example.com") {
            return VerificationResult(metadata: ResolvedMetadata(title: "Blog"), trustTier: .unverified, resolvedURL: raw)
        }
        let m = ResolvedMetadata(title: "Artigo Verificado", authors: ["Silva A", "Souza B"], journal: "N Engl J Med", year: 2022, volume: "1", issue: "2", pages: "10-15", doi: "10.1056/x")
        return VerificationResult(metadata: m, trustTier: .verified, resolvedURL: "https://doi.org/10.1056/x")
    }
}
