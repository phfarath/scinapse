// SciNapseKit/Sources/SciNapseKit/Models/Post.swift
import Foundation
import SwiftData

@Model
public final class Post {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var body: String
    public var status: PostStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var publishedAt: Date?
    public var topic: Topic?
    public var remoteID: String?
    public var syncStatus: SyncStatus

    @Relationship(deleteRule: .nullify, inverse: \Source.posts)
    public var sources: [Source] = []

    public init(title: String, body: String, status: PostStatus = .draft) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.status = status
        self.createdAt = Date()
        self.updatedAt = Date()
        self.publishedAt = nil
        self.remoteID = nil
        self.syncStatus = .pending
    }
}
