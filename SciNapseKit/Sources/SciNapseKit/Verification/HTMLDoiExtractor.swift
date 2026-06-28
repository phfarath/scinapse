// SciNapseKit/Sources/SciNapseKit/Verification/HTMLDoiExtractor.swift
import Foundation

public enum HTMLDoiExtractor {
    private static let metaNames = ["citation_doi", "dc.identifier", "prism.doi", "bepress_citation_doi"]

    public static func extractDOI(fromHTML html: String) -> String? {
        // 1. <meta name="citation_doi" content="...">  (case-insensitive no name)
        for match in metaTags(in: html) {
            if metaNames.contains(match.name.lowercased()), let doi = IdentifierParser.extractDOI(in: match.content) {
                return doi
            }
        }
        // 2. Qualquer DOI no HTML (fallback — JSON-LD, links doi.org, etc.)
        return IdentifierParser.extractDOI(in: html)
    }

    public static func extractTitle(fromHTML html: String) -> String? {
        guard let r = html.range(of: #"(?is)<title[^>]*>(.*?)</title>"#, options: .regularExpression) else { return nil }
        let inner = String(html[r])
            .replacingOccurrences(of: #"(?is)</?title[^>]*>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    private struct Meta { let name: String; let content: String }
    private static func metaTags(in html: String) -> [Meta] {
        var result: [Meta] = []
        let pattern = #"(?is)<meta\s+[^>]*?name=["']([^"']+)["'][^>]*?content=["']([^"']*)["'][^>]*?>"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let ns = html as NSString
        regex?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 3 else { return }
            result.append(Meta(name: ns.substring(with: m.range(at: 1)), content: ns.substring(with: m.range(at: 2))))
        }
        return result
    }
}
