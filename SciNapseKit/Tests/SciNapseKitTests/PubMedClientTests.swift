// SciNapseKit/Tests/SciNapseKitTests/PubMedClientTests.swift
import XCTest
@testable import SciNapseKit

final class PubMedClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func test_resolveDOI_fromConverter() async {
        StubURLProtocol.handler = { req in
            let json = #"{"status":"ok","records":[{"pmid":"33535474","doi":"10.3390/ijerph18031290"}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let client = PubMedClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let doi = await client.resolveDOI(pmid: "33535474")
        XCTAssertEqual(doi, "10.3390/ijerph18031290")
    }

    func test_fetchSummary_parsesMetadata() async throws {
        StubURLProtocol.handler = { req in
            let json = #"""
            {"result":{"33535474":{"uid":"33535474","title":"BRAINballs Program.",
            "fulljournalname":"Int J Environ Res Public Health","pubdate":"2021 Feb 1",
            "volume":"18","issue":"3","pages":"1290",
            "authors":[{"name":"Pham VH"},{"name":"Tran TN"}],
            "articleids":[{"idtype":"doi","value":"10.3390/ijerph18031290"}]},"uids":["33535474"]}}
            """#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let client = PubMedClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let meta = try await client.fetchSummary(pmid: "33535474")
        XCTAssertEqual(meta.title, "BRAINballs Program.")
        XCTAssertEqual(meta.journal, "Int J Environ Res Public Health")
        XCTAssertEqual(meta.year, 2021)
        XCTAssertEqual(meta.authors, ["Pham VH", "Tran TN"])
        XCTAssertEqual(meta.doi, "10.3390/ijerph18031290")
        XCTAssertEqual(meta.pmid, "33535474")
    }
}
