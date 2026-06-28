// SciNapseKit/Tests/SciNapseKitTests/IdentifierParserTests.swift
import XCTest
@testable import SciNapseKit

final class IdentifierParserTests: XCTestCase {
    func test_bareDOI() {
        XCTAssertEqual(IdentifierParser.parse("10.1177/1758835920922055"), .doi("10.1177/1758835920922055"))
    }
    func test_doiURL_extractsDOI() {
        XCTAssertEqual(IdentifierParser.parse("https://doi.org/10.1038/nature12373"), .doi("10.1038/nature12373"))
    }
    func test_barePMID() {
        XCTAssertEqual(IdentifierParser.parse("33535474"), .pmid("33535474"))
    }
    func test_pubmedURL_extractsPMID() {
        XCTAssertEqual(IdentifierParser.parse("https://pubmed.ncbi.nlm.nih.gov/33535474/"), .pmid("33535474"))
    }
    func test_pmidWithLabel() {
        XCTAssertEqual(IdentifierParser.parse("PMID: 12345678"), .pmid("12345678"))
    }
    func test_arbitraryURL() {
        guard case .url(let u) = IdentifierParser.parse("https://www.who.int/news/item/abc") else {
            return XCTFail("esperava .url")
        }
        XCTAssertEqual(u.host, "www.who.int")
    }
    func test_garbage_isUnknown() {
        XCTAssertEqual(IdentifierParser.parse("isso não é nada"), .unknown)
    }
    func test_kind_mapsCorrectly() {
        XCTAssertEqual(IdentifierParser.kind(for: "10.1056/x"), .doi)
        XCTAssertEqual(IdentifierParser.kind(for: "123"), .pmid)
        XCTAssertEqual(IdentifierParser.kind(for: "https://x.com"), .url)
    }
}
