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
    func test_extractAll_dedupsAndFindsMultiple() {
        let text = "Veja 10.1056/NEJMoa2034577 e https://pubmed.ncbi.nlm.nih.gov/33535474/ e PMID: 12345678 e https://www.who.int/x e 10.1056/NEJMoa2034577"
        let ids = IdentifierParser.extractAll(in: text)
        XCTAssertEqual(ids.count, 4)
        XCTAssertTrue(ids.contains("10.1056/NEJMoa2034577"))
        XCTAssertTrue(ids.contains("33535474"))
        XCTAssertTrue(ids.contains("12345678"))
        XCTAssertTrue(ids.contains(where: { $0.contains("who.int") }))
    }

    func test_extractAll_keepsBarePMIDs() {
        // Comportamento legado usado pelo "Adicionar fontes": número solto = PMID.
        XCTAssertEqual(IdentifierParser.extractAll(in: "33535474 12345678"), ["33535474", "12345678"])
    }

    func test_extractAllInProse_ignoresBareNumbers_keepsLabeledAndDOIs() {
        let text = "Estudo com 664 pacientes nas primeiras 24h. PMID: 12345678 e 10.1056/NEJMoa2034577 e https://www.who.int/x"
        let ids = IdentifierParser.extractAllInProse(in: text)
        XCTAssertEqual(ids.count, 3)                        // 664 e 24 NÃO entram
        XCTAssertFalse(ids.contains("664"))
        XCTAssertFalse(ids.contains("24"))
        XCTAssertTrue(ids.contains("12345678"))            // PMID rotulado entra
        XCTAssertTrue(ids.contains("10.1056/NEJMoa2034577"))
        XCTAssertTrue(ids.contains(where: { $0.contains("who.int") }))
    }
}
