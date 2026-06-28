// SciNapseKit/Tests/SciNapseKitTests/TypesTests.swift
import XCTest
@testable import SciNapseKit

final class TypesTests: XCTestCase {
    func test_retractionNone_andOAUnknown_constants() {
        XCTAssertEqual(RetractionInfo.none.status, .none)
        XCTAssertFalse(OpenAccessInfo.unknown.isOpenAccess)
    }
    func test_resolvedMetadata_isEquatable() {
        let a = ResolvedMetadata(title: "T", authors: ["X Y"])
        let b = ResolvedMetadata(title: "T", authors: ["X Y"])
        XCTAssertEqual(a, b)
    }
}
