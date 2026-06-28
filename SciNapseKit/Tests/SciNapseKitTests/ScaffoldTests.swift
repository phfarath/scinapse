// SciNapseKit/Tests/SciNapseKitTests/ScaffoldTests.swift
import XCTest
@testable import SciNapseKit

final class ScaffoldTests: XCTestCase {
    func test_userAgent_containsMailtoEmail() {
        XCTAssertTrue(Config.userAgent.contains("mailto:"))
        XCTAssertTrue(Config.userAgent.contains(Config.contactEmail))
    }
    func test_openAlexKey_defaultsNil() {
        XCTAssertNil(Config.openAlexAPIKey)
    }
    func test_appError_equatable() {
        XCTAssertEqual(AppError.offline, AppError.offline)
    }
}
