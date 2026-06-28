// SciNapseKit/Sources/SciNapseKit/Verification/AbstractReconstructor.swift
import Foundation

public enum AbstractReconstructor {
    public static func reconstruct(_ index: [String: [Int]]?) -> String? {
        guard let index, !index.isEmpty else { return nil }
        var maxPos = 0
        for positions in index.values { if let m = positions.max() { maxPos = max(maxPos, m) } }
        var words = Array(repeating: "", count: maxPos + 1)
        for (word, positions) in index {
            for pos in positions where pos >= 0 && pos <= maxPos { words[pos] = word }
        }
        let joined = words.filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
