// SciNapseKit/Tests/SciNapseKitTests/SourceFetcherTests.swift
import XCTest
import SwiftData
@testable import SciNapseKit

struct StubResolver: MetadataResolving {
    let result: Result<VerificationResult, Error>
    func verify(_ raw: String) async throws -> VerificationResult {
        switch result { case .success(let r): return r; case .failure(let e): throw e }
    }
}

final class SourceFetcherTests: XCTestCase {
    private func container() throws -> ModelContainer { try ModelContainerFactory.make(inMemory: true) }

    func test_addSource_verified_populatesMetadataAndCitation() async throws {
        let container = try container()
        let meta = ResolvedMetadata(title: "T", authors: ["Bee A"], journal: "J", year: 2020, doi: "10.1056/x")
        let result = VerificationResult(metadata: meta, trustTier: .verified, resolvedURL: "https://doi.org/10.1056/x")
        let resolver = StubResolver(result: .success(result))
        let fetcher = SourceFetcher(modelContainer: container)

        let id = await fetcher.addSource(rawInput: "10.1056/x", topicID: nil, postID: nil, savedStandalone: true, using: resolver)

        let ctx = ModelContext(container)
        let source = ctx.model(for: id) as? Source
        XCTAssertEqual(source?.trustTier, .verified)
        XCTAssertEqual(source?.verificationState, .completed)
        XCTAssertEqual(source?.title, "T")
        XCTAssertEqual(source?.normalizedDOI, "10.1056/x")
        XCTAssertNotNil(source?.formattedCitation)
        XCTAssertTrue(source?.savedStandalone == true)
    }

    func test_addSource_offline_marksPending() async throws {
        let container = try container()
        let resolver = StubResolver(result: .failure(AppError.offline))
        let fetcher = SourceFetcher(modelContainer: container)
        let id = await fetcher.addSource(rawInput: "10.1056/x", topicID: nil, postID: nil, savedStandalone: false, using: resolver)
        let ctx = ModelContext(container)
        let source = ctx.model(for: id) as? Source
        XCTAssertEqual(source?.verificationState, .pending)
        XCTAssertEqual(source?.trustTier, .unverified)
    }

    func test_reverify_updatesPendingSource() async throws {
        let container = try container()
        let fetcher = SourceFetcher(modelContainer: container)
        let id = await fetcher.addSource(rawInput: "10.1056/x", topicID: nil, postID: nil, savedStandalone: false,
                                         using: StubResolver(result: .failure(AppError.offline)))
        let meta = ResolvedMetadata(title: "Now resolved", authors: ["X Y"], journal: "J", year: 2021, doi: "10.1056/x")
        let good = VerificationResult(metadata: meta, trustTier: .verified)
        await fetcher.reverify(sourceID: id, using: StubResolver(result: .success(good)))
        let ctx = ModelContext(container)
        let source = ctx.model(for: id) as? Source
        XCTAssertEqual(source?.verificationState, .completed)
        XCTAssertEqual(source?.title, "Now resolved")
    }
}
