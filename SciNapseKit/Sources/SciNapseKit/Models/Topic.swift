// SciNapseKit/Sources/SciNapseKit/Models/Topic.swift
import Foundation
import SwiftData

@Model
public final class Topic {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var colorHex: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var remoteID: String?
    public var syncStatus: SyncStatus

    @Relationship(deleteRule: .cascade, inverse: \Post.topic)
    public var posts: [Post] = []

    public init(title: String, colorHex: String? = nil) {
        self.id = UUID()
        self.title = title
        self.colorHex = colorHex
        self.createdAt = Date()
        self.updatedAt = Date()
        self.remoteID = nil
        self.syncStatus = .pending
    }
}
