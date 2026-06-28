// SciNapseKit/Tests/SciNapseKitTests/ModelsTests.swift
import XCTest
import SwiftData
@testable import SciNapseKit

@MainActor
final class ModelsTests: XCTestCase {
    func test_cascadeDelete_topicRemovesPosts_butKeepsStandaloneSources() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let ctx = container.mainContext

        let topic = Topic(title: "Cardiologia")
        ctx.insert(topic)
        let post = Post(title: "Achado", body: "Resumo")
        post.topic = topic
        ctx.insert(post)
        let cited = Source(rawInput: "10.1/x", kind: .doi)
        ctx.insert(cited)
        post.sources.append(cited)

        let saved = Source(rawInput: "10.2/y", kind: .doi)
        saved.savedStandalone = true
        ctx.insert(saved)
        try ctx.save()

        ctx.delete(topic)
        try ctx.save()

        let posts = try ctx.fetch(FetchDescriptor<Post>())
        let sources = try ctx.fetch(FetchDescriptor<Source>())
        XCTAssertEqual(posts.count, 0, "post deve ser apagado em cascata com o tópico")
        // .nullify mantém as Sources existindo
        XCTAssertEqual(sources.count, 2, "sources não são apagadas ao deletar o tópico")
    }

    func test_manyToMany_postSources_roundtrips() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let ctx = container.mainContext
        let post = Post(title: "P", body: "B")
        ctx.insert(post)
        let s = Source(rawInput: "10.1/x", kind: .doi)
        ctx.insert(s)
        post.sources.append(s)
        try ctx.save()
        XCTAssertEqual(post.sources.first?.rawInput, "10.1/x")
        XCTAssertEqual(s.posts.first?.title, "P")
    }

    func test_defaults_uuidAndTimestamps() throws {
        let t = Topic(title: "X")
        XCTAssertEqual(t.syncStatus, .pending)
        XCTAssertNil(t.remoteID)
        XCTAssertNotNil(t.id)
    }
}
