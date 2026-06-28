// SciNapseKit/Tests/SciNapseKitTests/CrossrefClientTests.swift
import XCTest
@testable import SciNapseKit

final class CrossrefClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    private func stub(_ json: String, status: Int = 200) {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
    }

    func test_parsesMetadata() async throws {
        stub(#"""
        {"status":"ok","message":{"DOI":"10.1056/x","title":["Solid-organ transplantation"],
        "container-title":["N Engl J Med"],"type":"journal-article",
        "issued":{"date-parts":[[2002,7,25]]},"volume":"347","issue":"4","page":"284-287",
        "author":[{"given":"Samuel D.","family":"Halpern","sequence":"first"}]}}
        """#)
        let client = CrossrefClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let (meta, retraction) = try await client.fetch(doi: "10.1056/x")
        XCTAssertEqual(meta.title, "Solid-organ transplantation")
        XCTAssertEqual(meta.journal, "N Engl J Med")
        XCTAssertEqual(meta.year, 2002)
        XCTAssertEqual(meta.authors, ["Halpern SD"])
        XCTAssertEqual(meta.volume, "347")
        XCTAssertEqual(retraction.status, .none)
    }

    func test_detectsRetraction() async throws {
        stub(#"""
        {"status":"ok","message":{"DOI":"10.1177/1758835920922055","title":["RETRACTED: Myc"],
        "container-title":["X"],"issued":{"date-parts":[[2020,5,1]]},
        "updated-by":[{"DOI":"10.1/notice","type":"retraction","label":"Retraction",
        "source":"retraction-watch","updated":{"date-parts":[[2023,4,22]]}},
        {"DOI":"10.1/notice","type":"retraction","label":"Retraction","source":"publisher",
        "updated":{"date-parts":[[2023,4,22]]}}]}}
        """#)
        let client = CrossrefClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let (_, retraction) = try await client.fetch(doi: "10.1177/1758835920922055")
        XCTAssertEqual(retraction.status, .retracted)
        XCTAssertEqual(retraction.noticeDOI, "10.1/notice")
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: retraction.date!), 2023)
    }

    func test_titlePrefixRetracted_withoutUpdatedBy() async throws {
        stub(#"{"status":"ok","message":{"DOI":"10.1/x","title":["RETRACTED: Some study"],"container-title":["J"],"issued":{"date-parts":[[2019]]}}}"#)
        let client = CrossrefClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let (meta, retraction) = try await client.fetch(doi: "10.1/x")
        XCTAssertEqual(retraction.status, .retracted)
        // o prefixo "RETRACTED:" deve ser removido do título exibido
        XCTAssertEqual(meta.title, "Some study")
    }

    func test_throwsNotFoundOn404() async {
        stub("Resource not found.", status: 404)
        let client = CrossrefClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        do { _ = try await client.fetch(doi: "10.9999/missing"); XCTFail("esperava erro") }
        catch { XCTAssertEqual(error as? AppError, .notFound) }
    }
}
