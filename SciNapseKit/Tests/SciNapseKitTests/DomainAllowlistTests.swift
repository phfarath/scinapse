// SciNapseKit/Tests/SciNapseKitTests/DomainAllowlistTests.swift
import XCTest
@testable import SciNapseKit

final class DomainAllowlistTests: XCTestCase {
    func test_recognizesExactDomain() {
        XCTAssertTrue(DomainAllowlist.isRecognized(URL(string: "https://www.who.int/news/x")!))
    }
    func test_recognizesSubdomain() {
        XCTAssertTrue(DomainAllowlist.isRecognized(URL(string: "https://academic.oup.com/article/1")!))
    }
    func test_rejectsRandomBlog() {
        XCTAssertFalse(DomainAllowlist.isRecognized(URL(string: "https://meublog.example.com/post")!))
    }
    func test_recognizesBrazilianGov() {
        XCTAssertTrue(DomainAllowlist.isRecognized(URL(string: "https://www.gov.br/anvisa/pt-br")!) ||
                      DomainAllowlist.isRecognized(URL(string: "https://anvisa.gov.br/x")!))
    }
}
