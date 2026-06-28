// SciNapseKit/Tests/SciNapseKitTests/MetadataServiceTests.swift
import XCTest
@testable import SciNapseKit

final class MetadataServiceTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func test_doi_resolvesVerified() async throws {
        StubURLProtocol.handler = { req in
            let host = req.url!.host ?? ""
            let json: String
            if host.contains("crossref") {
                json = #"{"status":"ok","message":{"DOI":"10.1056/x","title":["T"],"container-title":["J"],"issued":{"date-parts":[[2020]]},"author":[{"given":"A","family":"Bee"}]}}"#
            } else { // unpaywall
                json = #"{"is_oa":false,"oa_status":"closed","best_oa_location":null}"#
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let service = MetadataService(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let result = try await service.verify("10.1056/x")
        XCTAssertEqual(result.trustTier, .verified)
        XCTAssertEqual(result.metadata.title, "T")
        XCTAssertEqual(result.metadata.authors, ["Bee A"])
    }

    func test_recognizedURL_withoutDOI() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("<html><title>OMS</title>sem doi aqui</html>".utf8))
        }
        let service = MetadataService(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let result = try await service.verify("https://www.who.int/news/item/x")
        XCTAssertEqual(result.trustTier, .recognized)
    }

    func test_unknownURL_isUnverified() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("<html>nada</html>".utf8))
        }
        let service = MetadataService(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let result = try await service.verify("https://blog.example.com/post")
        XCTAssertEqual(result.trustTier, .unverified)
    }

    func test_offline_throws() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let service = MetadataService(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        do { _ = try await service.verify("10.1056/x"); XCTFail("esperava offline") }
        catch { XCTAssertEqual(error as? AppError, .offline) }
    }
}
