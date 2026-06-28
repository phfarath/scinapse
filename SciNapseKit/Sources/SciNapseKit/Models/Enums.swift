// SciNapseKit/Sources/SciNapseKit/Models/Enums.swift
import Foundation

public enum SyncStatus: String, Codable, CaseIterable, Sendable { case pending, synced, conflict }
public enum PostStatus: String, Codable, CaseIterable, Sendable { case draft, published }
public enum SourceKind: String, Codable, CaseIterable, Sendable { case doi, pmid, url }
public enum TrustTier: String, Codable, CaseIterable, Sendable { case verified, recognized, unverified }
public enum VerificationState: String, Codable, CaseIterable, Sendable { case pending, completed, failed }
public enum RetractionStatus: String, Codable, CaseIterable, Sendable { case none, retracted, correction, concern }
