// SciNapseKit/Tests/SciNapseKitTests/EnumsTests.swift
import XCTest
@testable import SciNapseKit

final class EnumsTests: XCTestCase {
    func test_rawValues_areStable() {
        XCTAssertEqual(TrustTier.verified.rawValue, "verified")
        XCTAssertEqual(RetractionStatus.concern.rawValue, "concern")
        XCTAssertEqual(PostStatus.published.rawValue, "published")
        XCTAssertEqual(VerificationState.pending.rawValue, "pending")
        XCTAssertEqual(SourceKind.doi.rawValue, "doi")
        XCTAssertEqual(SyncStatus.synced.rawValue, "synced")
    }
}
