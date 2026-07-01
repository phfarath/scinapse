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

    /// Extrai todos os identificadores (DOIs, PMIDs, URLs) de um texto livre,
    /// deduplicados e na ordem de aparição. Usado para adicionar fontes em lote
    /// a partir de uma lista já identificada (aceita PMIDs "soltos").
    public static func extractAll(in text: String) -> [String] {
        extractIdentifiers(in: text, includeBarePMIDs: true)
    }

    /// Como `extractAll`, mas ignora números "soltos" — em prosa eles são quase
    /// sempre anos/quantidades (ex.: "664 pacientes", "24h"), não PMIDs. Use ao
    /// extrair fontes de texto corrido colado; DOIs, PMIDs rotulados ("PMID: x"),
    /// URLs do PubMed e links http continuam sendo capturados.
    public static func extractAllInProse(in text: String) -> [String] {
        extractIdentifiers(in: text, includeBarePMIDs: false)
    }

    private static func extractIdentifiers(in text: String, includeBarePMIDs: Bool) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        func add(key: String, value: String) {
            if seen.insert(key).inserted { results.append(value) }
        }
        for raw in regexMatches(doiPattern, in: text) {
            var d = raw
            while let last = d.last, ".,;)\"'>".contains(last) { d.removeLast() }
            add(key: "doi:" + d.lowercased(), value: d)
        }
        for raw in regexMatches(#"pubmed\.ncbi\.nlm\.nih\.gov/[1-9]\d{0,7}"#, in: text) {
            if let pmid = raw.split(separator: "/").last.map(String.init) { add(key: "pmid:" + pmid, value: pmid) }
        }
        for cap in regexCaptures(#"(?i)PMID[:\s]+([1-9]\d{0,7})"#, in: text) {
            add(key: "pmid:" + cap, value: cap)
        }
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }).map(String.init)
        for token in tokens {
            switch parse(token) {
            case .url(let u):
                let s = u.absoluteString
                if extractDOI(in: s) == nil && extractPMID(in: s) == nil { add(key: "url:" + s.lowercased(), value: s) }
            case .pmid(let p): if includeBarePMIDs { add(key: "pmid:" + p, value: p) }
            case .doi(let d): add(key: "doi:" + d.lowercased(), value: d)
            case .unknown: break
            }
        }
        return results
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
    private static func regexCaptures(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }

    private static func looksLikeURL(_ s: String) -> Bool {
        s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://")
    }
}
