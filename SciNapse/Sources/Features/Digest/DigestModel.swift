// SciNapse/Sources/Features/Digest/DigestModel.swift
import Foundation
import SciNapseKit

struct DigestItem: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let citations: [String]
    let publishedAt: Date
}

struct DigestModel {
    let topicTitle: String
    let from: Date
    let to: Date
    let items: [DigestItem]
}

enum DigestBuilder {
    static func build(topicTitle: String, posts: [Post], now: Date, days: Int = 7) -> DigestModel {
        let from = now.addingTimeInterval(-Double(days) * 86400)
        let items = posts
            .filter { $0.status == .published }
            .filter { let d = $0.publishedAt ?? $0.createdAt; return d >= from && d <= now }
            .sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }
            .map { post in
                DigestItem(
                    title: post.title,
                    body: post.body,
                    citations: post.sources.map {
                        let base = $0.formattedCitation ?? ($0.title ?? $0.rawInput)
                        let flag = $0.retractionStatus != .none ? " [RETRATADO]" : ""
                        return base + flag
                    },
                    publishedAt: post.publishedAt ?? post.createdAt
                )
            }
        return DigestModel(topicTitle: topicTitle, from: from, to: now, items: items)
    }
}

enum DigestTextRenderer {
    static func markdown(_ model: DigestModel) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        var lines = [
            "# \(model.topicTitle) — principais publicações da semana",
            "_\(df.string(from: model.from)) – \(df.string(from: model.to))_",
            ""
        ]
        if model.items.isEmpty {
            lines.append("Nenhum post publicado neste período.")
        }
        for item in model.items {
            lines.append("## \(item.title)")
            lines.append(item.body)
            if !item.citations.isEmpty {
                lines.append("")
                lines.append("**Fontes:**")
                for c in item.citations { lines.append("- \(c)") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
