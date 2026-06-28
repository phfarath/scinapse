// SciNapse/Sources/Features/Sources/SourcePreviewView.swift
import SwiftUI
import SciNapseKit

struct SourcePreviewView: View {
    let source: Source

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if source.retractionStatus != .none {
                Text("Artigo retratado\(source.retractionDate.map { " em \(yearOf($0))" } ?? "")")
                    .font(.subheadline.bold()).foregroundStyle(.red)
            }
            Text(source.title ?? source.rawInput).font(.headline)
            if !source.authors.isEmpty {
                Text(source.authors.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
            }
            if let j = source.journal {
                Text("\(j)\(source.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
            }
            SourceBadge(tier: source.trustTier, retraction: source.retractionStatus)
            if source.isOpenAccess, let oa = source.oaURL, let url = URL(string: oa) {
                Link("Acesso aberto", destination: url).font(.caption)
            }
            if let cit = source.formattedCitation {
                Text(cit).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func yearOf(_ d: Date) -> Int { Calendar.current.component(.year, from: d) }
}
