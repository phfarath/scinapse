// SciNapseKit/Tests/SciNapseKitTests/UnpaywallClientTests.swift
import XCTest
@testable import SciNapseKit

final class UnpaywallClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func test_parsesOpenAccess() async {
        StubURLProtocol.handler = { req in
            let json = #"{"is_oa":true,"oa_status":"gold","best_oa_location":{"url":"https://x/pdf","url_for_pdf":"https://x/pdf"}}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let client = UnpaywallClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let oa = await client.fetch(doi: "10.1056/x")
        XCTAssertTrue(oa.isOpenAccess)
        XCTAssertEqual(oa.status, "gold")
        XCTAssertEqual(oa.url, "https://x/pdf")
    }

    func test_404_returnsUnknown() async {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data("<h1>Not Found</h1>".utf8))
        }
        let client = UnpaywallClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let oa = await client.fetch(doi: "10.9999/missing")
        XCTAssertFalse(oa.isOpenAccess)
    }
}
