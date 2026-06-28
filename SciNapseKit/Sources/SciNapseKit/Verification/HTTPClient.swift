// SciNapseKit/Sources/SciNapseKit/Verification/HTTPClient.swift
import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let finalURL: URL?
}

public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public final class LiveHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let maxRetries: Int

    public init(session: URLSession = .shared, maxRetries: Int = 3) {
        self.session = session
        self.maxRetries = maxRetries
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var attempt = 0
        while true {
            var req = URLRequest(url: url, timeoutInterval: 10)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw AppError.invalidResponse }
                if (http.statusCode == 429 || http.statusCode >= 500), attempt < maxRetries {
                    attempt += 1
                    let backoff = pow(2.0, Double(attempt)) * 0.2 + Double.random(in: 0...0.2)
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    continue
                }
                return HTTPResponse(data: data, status: http.statusCode, finalURL: http.url)
            } catch let urlError as URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                    throw AppError.offline
                default:
                    // timeout e demais erros: retry enquanto houver tentativas; senão repropaga
                    if attempt < maxRetries { attempt += 1; continue }
                    throw urlError
                }
            }
        }
    }
}
