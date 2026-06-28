// SciNapseKit/Tests/SciNapseKitTests/AbstractReconstructorTests.swift
import XCTest
@testable import SciNapseKit

final class AbstractReconstructorTests: XCTestCase {
    func test_reconstructsInOrder() {
        let idx = ["Despite": [0], "growing": [1], "interest": [2], "in": [3, 5], "OA": [4]]
        XCTAssertEqual(AbstractReconstructor.reconstruct(idx), "Despite growing interest in OA in")
    }
    func test_nilWhenEmpty() {
        XCTAssertNil(AbstractReconstructor.reconstruct(nil))
        XCTAssertNil(AbstractReconstructor.reconstruct([:]))
    }
}
