// SciNapseKit/Tests/SciNapseKitTests/TrustClassifierTests.swift
import XCTest
@testable import SciNapseKit

final class TrustClassifierTests: XCTestCase {
    func test_resolvedIdentifier_isVerified() {
        XCTAssertEqual(TrustClassifier.tier(resolvedIdentifier: true, url: nil), .verified)
    }
    func test_recognizedDomain_isRecognized() {
        XCTAssertEqual(TrustClassifier.tier(resolvedIdentifier: false, url: URL(string: "https://who.int/x")!), .recognized)
    }
    func test_unknownDomain_isUnverified() {
        XCTAssertEqual(TrustClassifier.tier(resolvedIdentifier: false, url: URL(string: "https://blog.example.com")!), .unverified)
    }
    func test_noURL_noIdentifier_isUnverified() {
        XCTAssertEqual(TrustClassifier.tier(resolvedIdentifier: false, url: nil), .unverified)
    }
}
