// SciNapseKit/Sources/SciNapseKit/Verification/IdentifierParser.swift
import Foundation

public enum IdentifierParser {
    // Padrão canônico Crossref (case-insensitive). Removemos pontuação final no caller.
    private static let doiPattern = #"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+"#
    private static let pmidStrict = #"^[1-9]\d{0,7}$"#

    public static func parse(_ raw: String) -> ParsedIdentifier {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        // 1. DOI puro (string inteira é um DOI)
        if let doi = extractDOI(in: trimmed), trimmed.range(of: doiPattern, options: [.regularExpression, .caseInsensitive])?.lowerBound == trimmed.startIndex || trimmed.lowercased().hasPrefix("10.") {
            // string começa em "10." → trate como DOI puro
            if trimmed.lowercased().hasPrefix("10.") { return .doi(doi) }
        }
        // 2. PMID puro
        if trimmed.range(of: pmidStrict, options: .regularExpression) != nil {
            return .pmid(trimmed)
        }
        // 3. PMID rotulado ("PMID: 123") ou URL do PubMed
        if let pmid = extractPMID(in: trimmed) {
            if !looksLikeURL(trimmed) || trimmed.lowercased().contains("pubmed") {
                return .pmid(pmid)
            }
        }
        // 4. URL contendo DOI embutido (e.g. doi.org/10.xxx/...)
        if looksLikeURL(trimmed), let doi = extractDOI(in: trimmed) {
            return .doi(doi)
        }
        // 5. URL genérica
        if looksLikeURL(trimmed), let url = URL(string: trimmed) {
            return .url(url)
        }
        // 6. DOI embutido em texto livre
        if let doi = extractDOI(in: trimmed) { return .doi(doi) }
        return .unknown
    }

    public static func extractDOI(in text: String) -> String? {
        guard let range = text.range(of: doiPattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var doi = String(text[range])
        // Remove pontuação final capturada por engano
        while let last = doi.last, ".,;)\"'".contains(last) { doi.removeLast() }
        return doi
    }

    public static func extractPMID(in text: String) -> String? {
        // URL do PubMed
        if let r = text.range(of: #"pubmed\.ncbi\.nlm\.nih\.gov/([1-9]\d{0,7})"#, options: .regularExpression) {
            return text[r].split(separator: "/").last.map(String.init)
        }
        // "PMID: 123"
        if let r = text.range(of: #"(?i)PMID[:\s]+([1-9]\d{0,7})"#, options: .regularExpression) {
            return text[r].components(separatedBy: CharacterSet(charactersIn: ": ")).last
        }
        return nil
    }

    public static func kind(for raw: String) -> SourceKind {
        switch parse(raw) {
        case .doi: return .doi
        case .pmid: return .pmid
        case .url, .unknown: return .url
        }
    }

    private static func looksLikeURL(_ s: String) -> Bool {
        s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://")
    }
}
