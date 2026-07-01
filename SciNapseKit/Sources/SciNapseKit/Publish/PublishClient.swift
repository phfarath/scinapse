// SciNapseKit/Sources/SciNapseKit/Publish/PublishClient.swift
// Fase 2a — publica snapshots públicos (tópico inteiro, recorte semanal ou post único),
// despublica e lê o contador de visualizações. Página viva: reusa o slug guardado.
import Foundation

// MARK: - Escopo do recorte

public enum PublishScope: Sendable {
    case all        // todos os posts publicados do tópico
    case lastWeek   // só os últimos 7 dias
}

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

/// Stats agregados de uma página publicada (views + reações + cliques em fonte).
public struct PageStats: Sendable, Codable {
    public let views: Int
    public let useful: Int
    public let notUseful: Int
    public let sourceClicks: Int

    enum CodingKeys: String, CodingKey {
        case views
        case useful
        case notUseful = "not_useful"
        case sourceClicks = "source_clicks"
    }
}

public enum PublishError: Error, LocalizedError {
    case noSyntheses
    case network
    case server(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .noSyntheses: return "Publique ao menos um post (com fonte) antes de gerar a página."
        case .network: return "Falha de conexão."
        case .server(let status, _): return "O servidor recusou a operação (HTTP \(status))."
        }
    }
}

// MARK: - Cliente

public struct PublishClient: Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    /// Publica o tópico (escopo Tudo/Última semana). Página viva via `topic.remoteID`.
    @MainActor
    public func publish(topic: Topic, scope: PublishScope = .all) async throws -> PublishResult {
        let snapshot = Self.snapshot(from: topic, scope: scope)
        guard !snapshot.syntheses.isEmpty else { throw PublishError.noSyntheses }
        return try await send(slug: topic.remoteID, title: topic.title, data: snapshot)
    }

    /// Publica um post único como página própria. Página viva via `post.remoteID`.
    @MainActor
    public func publish(post: Post) async throws -> PublishResult {
        let snapshot = Self.snapshot(fromPost: post)
        return try await send(slug: post.remoteID, title: post.title, data: snapshot)
    }

    /// Tira a página do ar (deleta a linha). Gated pelo PUBLISH_SECRET na função.
    public func unpublish(slug: String) async throws {
        struct Body: Encodable { let slug: String; let secret: String }
        _ = try await postFunction(path: "unpublish", body: Body(slug: slug, secret: Config.publishSecret))
    }

    /// Lê os stats (views + reações + cliques em fonte) de um slug via RPC `page_stats` (nil se falhar).
    public func stats(forSlug slug: String) async -> PageStats? {
        guard let url = URL(string: "\(Config.supabaseURL)/rest/v1/rpc/page_stats") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        struct Body: Encodable {
            let slug: String
            enum CodingKeys: String, CodingKey { case slug = "p_slug" }
        }
        guard let body = try? JSONEncoder().encode(Body(slug: slug)) else { return nil }
        req.httpBody = body
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(PageStats.self, from: data)
    }

    /// URL pública de um slug já publicado (reconstruída, sem rede).
    public static func publicURL(forSlug slug: String) -> URL? {
        URL(string: "\(Config.readerBaseURL)#\(slug)")
    }

    // MARK: - Rede

    private func send(slug: String?, title: String, data: PublishSnapshot) async throws -> PublishResult {
        struct Request: Encodable {
            let slug: String?
            let title: String
            let data: PublishSnapshot
            let secret: String
        }
        let payload = Request(slug: slug, title: title, data: data, secret: Config.publishSecret)
        let respData = try await postFunction(path: "publish", body: payload)
        return try JSONDecoder().decode(PublishResult.self, from: respData)
    }

    @discardableResult
    private func postFunction<B: Encodable>(path: String, body: B) async throws -> Data {
        guard let url = URL(string: "\(Config.supabaseURL)/functions/v1/\(path)") else { throw PublishError.network }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) } catch { throw PublishError.network }
        guard let http = response as? HTTPURLResponse else { throw PublishError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw PublishError.server(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Montagem do snapshot (roda no contexto do modelo)

    @MainActor
    static func snapshot(from topic: Topic, scope: PublishScope) -> PublishSnapshot {
        let iso = ISO8601DateFormatter()
        var posts = topic.posts.filter { $0.status == .published }
        if scope == .lastWeek {
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            posts = posts.filter { ($0.publishedAt ?? $0.createdAt) >= cutoff }
        }
        posts.sort { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }
        return PublishSnapshot(
            title: topic.title,
            publishedAt: iso.string(from: Date()),
            syntheses: posts.map { synthesisDTO($0, iso: iso) }
        )
    }

    @MainActor
    static func snapshot(fromPost post: Post) -> PublishSnapshot {
        let iso = ISO8601DateFormatter()
        return PublishSnapshot(
            title: post.title,
            publishedAt: iso.string(from: Date()),
            syntheses: [synthesisDTO(post, iso: iso)]
        )
    }

    @MainActor
    private static func synthesisDTO(_ post: Post, iso: ISO8601DateFormatter) -> SynthesisDTO {
        SynthesisDTO(
            id: post.id.uuidString,
            title: post.title,
            text: post.body,
            date: iso.string(from: post.publishedAt ?? post.createdAt),
            sources: post.sources.map(sourceDTO)
        )
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
