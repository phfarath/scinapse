// SciNapseKit/Sources/SciNapseKit/Verification/TrustClassifier.swift
import Foundation

public enum TrustClassifier {
    public static func tier(resolvedIdentifier: Bool, url: URL?) -> TrustTier {
        if resolvedIdentifier { return .verified }
        if let url, DomainAllowlist.isRecognized(url) { return .recognized }
        return .unverified
    }
}
