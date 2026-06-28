// SciNapseKit/Sources/SciNapseKit/Verification/UnpaywallClient.swift
import Foundation

public struct UnpaywallClient: Sendable {
    private let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    private struct Payload: Decodable {
        let isOA: Bool?
        let oaStatus: String?
        let bestOaLocation: Location?
        enum CodingKeys: String, CodingKey {
            case isOA = "is_oa", oaStatus = "oa_status", bestOaLocation = "best_oa_location"
        }
    }
    private struct Location: Decodable {
        let url: String?
        let urlForPdf: String?
        let urlForLandingPage: String?
        enum CodingKeys: String, CodingKey {
            case url, urlForPdf = "url_for_pdf", urlForLandingPage = "url_for_landing_page"
        }
    }

    public func fetch(doi: String) async -> OpenAccessInfo {
        let email = Config.contactEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Config.contactEmail
        guard let url = URL(string: "https://api.unpaywall.org/v2/\(doi)?email=\(email)") else { return .unknown }
        guard let resp = try? await http.get(url, headers: [:]), resp.status == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: resp.data) else {
            return .unknown
        }
        let bestURL = payload.bestOaLocation?.urlForPdf
            ?? payload.bestOaLocation?.urlForLandingPage
            ?? payload.bestOaLocation?.url
        return OpenAccessInfo(isOpenAccess: payload.isOA ?? false, status: payload.oaStatus, url: bestURL)
    }
}
