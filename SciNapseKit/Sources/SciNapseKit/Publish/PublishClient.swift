// SciNapseKit/Sources/SciNapseKit/Publish/PublishClient.swift
// Fase 2a — monta o snapshot público de um tópico (posts publicados + fontes)
// e chama a edge function `publish`. Página viva: reusa o slug guardado em Topic.remoteID.
import Foundation

// MARK: - DTOs do snapshot (contrato com a edge function `publish` e o reader)

public struct PublishSnapshot: Codable, Sendable {
    public var title: String
    public var publishedAt: String
    public var syntheses: [SynthesisDTO]
}

public struct SynthesisDTO: Codable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    public var date: String
    public var sources: [SourceDTO]
}

public struct SourceDTO: Codable, Sendable {
    public var title: String?
    public var authors: [String]
    public var container: String?
    public var year: Int?
    public var identifier: IdentifierDTO
    public var url: String?
    public var vancouver: String?
    public var tier: String
    public var retraction: String
}

public struct IdentifierDTO: Codable, Sendable {
    public var kind: String
    public var value: String
}

// MARK: - Resultado + erros

public struct PublishResult: Codable, Sendable {
    public let slug: String
    public let url: URL
}

public enum PublishError: Error, LocalizedError {
    case noSyntheses
    case network
    case server(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .noSyntheses: return "Publique ao menos um post neste tópico antes de gerar a página."
        case .network: return "Falha de conexão ao publicar."
        case .server(let status, _): return "O servidor recusou a publicação (HTTP \(status))."
        }
    }
}

// MARK: - Cliente

public struct PublishClient: Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    /// Monta o snapshot dos posts publicados do tópico e publica. Retorna slug + URL.
    /// O chamador deve gravar `result.slug` em `topic.remoteID` (página viva).
    @MainActor
    public func publish(topic: Topic) async throws -> PublishResult {
        let snapshot = Self.snapshot(from: topic)
        guard !snapshot.syntheses.isEmpty else { throw PublishError.noSyntheses }

        struct Request: Encodable {
            let slug: String?
            let title: String
            let data: PublishSnapshot
            let secret: String
        }
        let payload = Request(slug: topic.remoteID, title: topic.title, data: snapshot, secret: Config.publishSecret)

        guard let url = URL(string: "\(Config.supabaseURL)/functions/v1/publish") else { throw PublishError.network }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PublishError.network
        }
        guard let http = response as? HTTPURLResponse else { throw PublishError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw PublishError.server(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(PublishResult.self, from: data)
    }

    /// URL pública de um slug já publicado (reconstruída, sem rede).
    public static func publicURL(forSlug slug: String) -> URL? {
        URL(string: "\(Config.readerBaseURL)#\(slug)")
    }

    // MARK: - Montagem do snapshot (roda no contexto do modelo)

    @MainActor
    static func snapshot(from topic: Topic) -> PublishSnapshot {
        let iso = ISO8601DateFormatter()
        let posts = topic.posts
            .filter { $0.status == .published }
            .sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }

        let syntheses = posts.map { post in
            SynthesisDTO(
                id: post.id.uuidString,
                title: post.title,
                text: post.body,
                date: iso.string(from: post.publishedAt ?? post.createdAt),
                sources: post.sources.map(sourceDTO)
            )
        }
        return PublishSnapshot(title: topic.title, publishedAt: iso.string(from: Date()), syntheses: syntheses)
    }

    @MainActor
    private static func sourceDTO(_ s: Source) -> SourceDTO {
        let value = s.normalizedDOI ?? s.pmid ?? s.resolvedURL ?? s.rawInput
        let citation = (s.formattedCitation?.isEmpty == false) ? s.formattedCitation : s.title
        return SourceDTO(
            title: s.title,
            authors: s.authors,
            container: s.journal,
            year: s.year,
            identifier: IdentifierDTO(kind: s.kind.rawValue, value: value),
            url: bestURL(s),
            vancouver: citation,
            tier: s.trustTier.rawValue,
            retraction: s.retractionStatus.rawValue
        )
    }

    private static func bestURL(_ s: Source) -> String? {
        if let u = s.resolvedURL, !u.isEmpty { return u }
        if let d = s.normalizedDOI, !d.isEmpty { return "https://doi.org/\(d)" }
        if let oa = s.oaURL, !oa.isEmpty { return oa }
        return nil
    }
}
