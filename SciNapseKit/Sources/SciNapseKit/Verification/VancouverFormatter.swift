// SciNapseKit/Sources/SciNapseKit/Verification/VancouverFormatter.swift
import Foundation

public enum VancouverFormatter {
    public static func format(_ m: ResolvedMetadata) -> String {
        var parts: [String] = []

        // Authors
        if !m.authors.isEmpty {
            if m.authors.count <= 6 {
                parts.append(m.authors.joined(separator: ", ") + ".")
            } else {
                parts.append(m.authors.prefix(6).joined(separator: ", ") + ", et al.")
            }
        }
        // Title
        if let title = m.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            parts.append(title.hasSuffix(".") ? title : title + ".")
        }
        // Journal
        if let j = m.journal, !j.isEmpty { parts.append(j + ".") }

        // Date + location (vol/issue/pages)
        var dateStr = m.year.map { String($0) } ?? ""
        if let mo = m.month { dateStr += " \(mo)" }
        if let d = m.day { dateStr += " \(d)" }

        // Semicolon belongs between year and volume, not between year and bare pages.
        var loc = ""
        if let vol = m.volume {
            loc = ";" + vol
            if let iss = m.issue { loc += "(\(iss))" }
            if let pages = m.pages { loc += ":" + formatPages(pages) }
        } else if let pages = m.pages {
            loc = ":" + formatPages(pages)
        }
        if !dateStr.isEmpty || !loc.isEmpty {
            parts.append(dateStr + loc + ".")
        }
        // DOI
        if let doi = m.doi { parts.append("https://doi.org/\(doi)") }

        return parts.joined(separator: " ")
    }

    /// "284-287" -> "284-7". Reuses `abbreviatePages` (single source of truth).
    /// Non-range / e-location IDs (e.g. "e202301234") pass through unchanged.
    private static func formatPages(_ pages: String) -> String {
        let comps = pages.split(separator: "-", maxSplits: 1).map(String.init)
        guard comps.count == 2 else { return pages }
        return comps[0] + "-" + abbreviatePages(start: comps[0], end: comps[1])
    }

    /// NLM minimal-suffix rule: drops the leading digits of `end` that are
    /// identical to `start`. "287" vs "284" -> "7"; "1440" vs "1432" -> "40".
    /// Returns `end` unchanged when lengths differ, are non-numeric, or share no prefix.
    public static func abbreviatePages(start: String, end: String) -> String {
        guard start.count == end.count, start.allSatisfy(\.isNumber), end.allSatisfy(\.isNumber) else { return end }
        let s = Array(start), e = Array(end)
        var i = 0
        while i < e.count && s[i] == e[i] { i += 1 }
        return i == 0 ? end : String(e[i...])
    }
}
