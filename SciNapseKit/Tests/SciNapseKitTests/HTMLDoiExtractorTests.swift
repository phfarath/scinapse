// SciNapseKit/Tests/SciNapseKitTests/HTMLDoiExtractorTests.swift
import XCTest
@testable import SciNapseKit

final class HTMLDoiExtractorTests: XCTestCase {
    func test_citationDoiMeta() {
        let html = #"<html><head><meta name="citation_doi" content="10.1038/nature12373"><title>X</title></head></html>"#
        XCTAssertEqual(HTMLDoiExtractor.extractDOI(fromHTML: html), "10.1038/nature12373")
    }
    func test_dcIdentifierWithURL() {
        let html = #"<meta name="DC.identifier" content="https://doi.org/10.1056/abc">"#
        XCTAssertEqual(HTMLDoiExtractor.extractDOI(fromHTML: html), "10.1056/abc")
    }
    func test_jsonLD() {
        let html = #"<script type="application/ld+json">{"@type":"ScholarlyArticle","identifier":{"propertyID":"doi","value":"10.7717/zzz"}}</script>"#
        XCTAssertEqual(HTMLDoiExtractor.extractDOI(fromHTML: html), "10.7717/zzz")
    }
    func test_noDOI() {
        XCTAssertNil(HTMLDoiExtractor.extractDOI(fromHTML: "<html>nada</html>"))
    }
    func test_title() {
        XCTAssertEqual(HTMLDoiExtractor.extractTitle(fromHTML: "<title>Meu Artigo</title>"), "Meu Artigo")
    }
}
