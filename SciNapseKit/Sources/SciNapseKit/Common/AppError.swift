// SciNapseKit/Sources/SciNapseKit/Common/AppError.swift
import Foundation

public enum AppError: Error, Equatable {
    case offline
    case invalidResponse
    case notFound
    case rateLimited
    case unresolvable
}
