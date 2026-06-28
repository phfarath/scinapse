// SciNapseKit/Tests/SciNapseKitTests/HTTPClientTests.swift
import XCTest
@testable import SciNapseKit

final class HTTPClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func test_get_returnsBodyAndStatus() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("hello".utf8))
        }
        let client = LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0)
        let r = try await client.get(URL(string: "https://x.test/a")!, headers: ["User-Agent": "T"])
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(String(decoding: r.data, as: UTF8.self), "hello")
    }

    func test_get_forwardsHeaders() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), "SciNapse/1.0")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let client = LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0)
        _ = try await client.get(URL(string: "https://x.test")!, headers: ["User-Agent": "SciNapse/1.0"])
    }

    func test_offlineURLError_mapsToAppErrorOffline() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let client = LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0)
        do {
            _ = try await client.get(URL(string: "https://x.test")!, headers: [:])
            XCTFail("esperava AppError.offline")
        } catch {
            XCTAssertEqual(error as? AppError, .offline)
        }
    }
}
