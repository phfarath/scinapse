// SciNapse/Sources/Features/Posts/PostComposer.swift
import Foundation

enum PostComposer {
    static func canPublish(title: String, sourceCount: Int) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sourceCount >= 1
    }
}
