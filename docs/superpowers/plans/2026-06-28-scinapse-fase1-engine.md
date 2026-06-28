# SciNapseKit (Motor de Verificação) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir `SciNapseKit`, um Swift Package headless e 100% testável (`swift test` no macOS, sem simulador) com os modelos SwiftData, o motor de verificação algorítmica (DOI/PMID/URL → camadas de confiança + retração), formatação Vancouver e o `@ModelActor` de persistência.

**Architecture:** Pacote SwiftPM com três camadas — `Models` (SwiftData, sync-ready), `Verification` (parsing + clients de API públicas + orquestração, tudo injetável via protocolos para teste com `URLProtocol` stub), e `Persistence` (`@ModelActor SourceFetcher`). Sem dependências externas: apenas `URLSession` + `Codable` + `SwiftData`. O app SwiftUI (Plano 2) consome este pacote.

**Tech Stack:** Swift 6, SwiftData, Foundation/`URLSession`, XCTest. Plataformas: iOS 17.4 / macOS 14.

## Global Constraints

- **Deployment floor:** iOS 17.4, macOS 14. (Predicados SQL do SwiftData estáveis; SwiftData disponível no macOS p/ `swift test`.)
- **Zero dependências externas.** Nada de SPM/CocoaPods de terceiros. Só frameworks do sistema.
- **Sem segredos embutidos.** Crossref/Unpaywall/PubMed são keyless. OpenAlex (que exige key desde fev/2026) é opcional e desligado por padrão (`Config.openAlexAPIKey == nil`).
- **Polite pool obrigatório:** header `User-Agent: SciNapse/1.0 (mailto:<email>)` no Crossref; `?email=<email>` no Unpaywall (e-mail real, senão HTTP 422); `tool=SciNapse&email=<email>` no PubMed/PMC.
- **Identificadores ortogonais:** `TrustTier` (verified/recognized/unverified) e `RetractionStatus` (none/retracted/correction/concern) são independentes.
- **Regra de publicação (vive no app, Plano 2):** "ter ≥1 fonte", não "fonte verificada".
- **TDD:** cada task escreve o teste que falha antes da implementação. `swift test` deve ficar verde ao fim de cada task.
- **Timeout de rede:** 10s por request. Backoff exponencial + jitter em 429/5xx (máx. 3 tentativas).

## Shared Type Contracts (definidos nas Tasks 2 e 4; referenciados em todas as seguintes)

```
// Models/Enums.swift  (Task 2)
enum SyncStatus: String, Codable { case pending, synced, conflict }
enum PostStatus: String, Codable { case draft, published }
enum SourceKind: String, Codable { case doi, pmid, url }
enum TrustTier: String, Codable { case verified, recognized, unverified }
enum VerificationState: String, Codable { case pending, completed, failed }
enum RetractionStatus: String, Codable { case none, retracted, correction, concern }

// Verification/Types.swift  (Task 4)
struct ResolvedMetadata: Sendable, Equatable {
    var title: String?; var authors: [String]; var journal: String?
    var year: Int?; var month: String?; var day: Int?
    var volume: String?; var issue: String?; var pages: String?
    var abstract: String?; var workType: String?; var doi: String?; var pmid: String?
}
struct RetractionInfo: Sendable, Equatable { var status: RetractionStatus; var date: Date?; var noticeDOI: String? ; static let none }
struct OpenAccessInfo: Sendable, Equatable { var isOpenAccess: Bool; var status: String?; var url: String?; static let unknown }
enum ParsedIdentifier: Sendable, Equatable { case doi(String); case pmid(String); case url(URL); case unknown }
struct VerificationResult: Sendable, Equatable {
    var metadata: ResolvedMetadata; var trustTier: TrustTier
    var retraction: RetractionInfo; var openAccess: OpenAccessInfo; var resolvedURL: String?
}
protocol MetadataResolving: Sendable { func verify(_ raw: String) async throws -> VerificationResult }

// Verification/HTTPClient.swift  (Task 9)
struct HTTPResponse: Sendable { let data: Data; let status: Int; let finalURL: URL? }
protocol HTTPClient: Sendable { func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse }
```

---

### Task 1: Package scaffold + Config + AppError

**Files:**
- Create: `SciNapseKit/Package.swift`
- Create: `SciNapseKit/Sources/SciNapseKit/Common/Config.swift`
- Create: `SciNapseKit/Sources/SciNapseKit/Common/AppError.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/ScaffoldTests.swift`

**Interfaces:**
- Produces: `enum Config` com `static var contactEmail: String`, `static var userAgent: String`, `static var openAlexAPIKey: String?`, `static let pubmedTool: String`. `enum AppError: Error, Equatable { case offline, invalidResponse, notFound, rateLimited, unresolvable }`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/ScaffoldTests.swift
import XCTest
@testable import SciNapseKit

final class ScaffoldTests: XCTestCase {
    func test_userAgent_containsMailtoEmail() {
        XCTAssertTrue(Config.userAgent.contains("mailto:"))
        XCTAssertTrue(Config.userAgent.contains(Config.contactEmail))
    }
    func test_openAlexKey_defaultsNil() {
        XCTAssertNil(Config.openAlexAPIKey)
    }
    func test_appError_equatable() {
        XCTAssertEqual(AppError.offline, AppError.offline)
    }
}
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SciNapseKit",
    platforms: [.iOS("17.4"), .macOS(.v14)],
    products: [
        .library(name: "SciNapseKit", targets: ["SciNapseKit"])
    ],
    targets: [
        .target(name: "SciNapseKit"),
        .testTarget(name: "SciNapseKitTests", dependencies: ["SciNapseKit"])
    ]
)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd SciNapseKit && swift test`
Expected: FAIL — build error "cannot find 'Config' in scope".

- [ ] **Step 4: Implement Config + AppError**

```swift
// SciNapseKit/Sources/SciNapseKit/Common/Config.swift
import Foundation

public enum Config {
    /// Deve ser um e-mail real: o Unpaywall rejeita placeholders (HTTP 422).
    public static var contactEmail = "pedropontesfarath@gmail.com"
    public static var userAgent: String { "SciNapse/1.0 (mailto:\(contactEmail))" }
    /// Opcional (Fase 1.5). Desligado por padrão — OpenAlex exige key desde fev/2026.
    public static var openAlexAPIKey: String? = nil
    public static let pubmedTool = "SciNapse"
}
```

```swift
// SciNapseKit/Sources/SciNapseKit/Common/AppError.swift
import Foundation

public enum AppError: Error, Equatable {
    case offline
    case invalidResponse
    case notFound
    case rateLimited
    case unresolvable
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd SciNapseKit && swift test`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add SciNapseKit
git commit -m "feat(kit): scaffold SciNapseKit package + Config + AppError"
```

---

### Task 2: Domain enums

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Models/Enums.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/EnumsTests.swift`

**Interfaces:**
- Produces: os 6 enums do Shared Type Contracts (todos `String, Codable, CaseIterable, Sendable`).

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/EnumsTests.swift
import XCTest
@testable import SciNapseKit

final class EnumsTests: XCTestCase {
    func test_rawValues_areStable() {
        XCTAssertEqual(TrustTier.verified.rawValue, "verified")
        XCTAssertEqual(RetractionStatus.concern.rawValue, "concern")
        XCTAssertEqual(PostStatus.published.rawValue, "published")
        XCTAssertEqual(VerificationState.pending.rawValue, "pending")
        XCTAssertEqual(SourceKind.doi.rawValue, "doi")
        XCTAssertEqual(SyncStatus.synced.rawValue, "synced")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter EnumsTests`
Expected: FAIL — "cannot find type 'TrustTier' in scope".

- [ ] **Step 3: Implement enums**

```swift
// SciNapseKit/Sources/SciNapseKit/Models/Enums.swift
import Foundation

public enum SyncStatus: String, Codable, CaseIterable, Sendable { case pending, synced, conflict }
public enum PostStatus: String, Codable, CaseIterable, Sendable { case draft, published }
public enum SourceKind: String, Codable, CaseIterable, Sendable { case doi, pmid, url }
public enum TrustTier: String, Codable, CaseIterable, Sendable { case verified, recognized, unverified }
public enum VerificationState: String, Codable, CaseIterable, Sendable { case pending, completed, failed }
public enum RetractionStatus: String, Codable, CaseIterable, Sendable { case none, retracted, correction, concern }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter EnumsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit
git commit -m "feat(kit): domain enums (TrustTier, RetractionStatus, etc.)"
```

---

### Task 3: SwiftData models + container factory

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Models/Topic.swift`
- Create: `SciNapseKit/Sources/SciNapseKit/Models/Post.swift`
- Create: `SciNapseKit/Sources/SciNapseKit/Models/Source.swift`
- Create: `SciNapseKit/Sources/SciNapseKit/Models/SchemaV1.swift`
- Create: `SciNapseKit/Sources/SciNapseKit/Persistence/ModelContainerFactory.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/ModelsTests.swift`

**Interfaces:**
- Consumes: enums (Task 2).
- Produces: `@Model final class Topic`, `Post`, `Source` (campos conforme o spec §5). `enum SchemaV1: VersionedSchema`, `enum AppMigrationPlan: SchemaMigrationPlan`. `enum ModelContainerFactory { static func make(inMemory: Bool) throws -> ModelContainer }`.

- [ ] **Step 1: Write the failing test**

```swift
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
        let cited = Source(rawInput: "10.1056/x", kind: .doi)
        ctx.insert(cited)
        post.sources.append(cited)

        let saved = Source(rawInput: "10.2000/y", kind: .doi)
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
        let s = Source(rawInput: "10.1056/x", kind: .doi)
        ctx.insert(s)
        post.sources.append(s)
        try ctx.save()
        XCTAssertEqual(post.sources.first?.rawInput, "10.1056/x")
        XCTAssertEqual(s.posts.first?.title, "P")
    }

    func test_defaults_uuidAndTimestamps() throws {
        let t = Topic(title: "X")
        XCTAssertEqual(t.syncStatus, .pending)
        XCTAssertNil(t.remoteID)
        XCTAssertNotNil(t.id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter ModelsTests`
Expected: FAIL — "cannot find 'ModelContainerFactory'".

- [ ] **Step 3: Implement the models**

```swift
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
```

```swift
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
```

```swift
// SciNapseKit/Sources/SciNapseKit/Models/Source.swift
import Foundation
import SwiftData

@Model
public final class Source {
    @Attribute(.unique) public var id: UUID
    public var rawInput: String
    public var kind: SourceKind
    public var normalizedDOI: String?
    public var pmid: String?
    public var resolvedURL: String?

    public var title: String?
    public var authors: [String]
    public var journal: String?
    public var year: Int?
    public var month: String?
    public var day: Int?
    public var volume: String?
    public var issue: String?
    public var pages: String?
    public var abstract: String?
    public var workType: String?

    public var trustTier: TrustTier
    public var verificationState: VerificationState
    public var retractionStatus: RetractionStatus
    public var retractionDate: Date?
    public var retractionNoticeDOI: String?

    public var isOpenAccess: Bool
    public var oaStatus: String?
    public var oaURL: String?

    public var formattedCitation: String?
    public var savedStandalone: Bool
    public var topic: Topic?

    public var createdAt: Date
    public var updatedAt: Date
    public var fetchedAt: Date?
    public var remoteID: String?
    public var syncStatus: SyncStatus

    // Lado inverso do N↔N — SEM @Relationship (declarado em Post.sources)
    public var posts: [Post] = []

    public init(rawInput: String, kind: SourceKind) {
        self.id = UUID()
        self.rawInput = rawInput
        self.kind = kind
        self.authors = []
        self.trustTier = .unverified
        self.verificationState = .pending
        self.retractionStatus = .none
        self.isOpenAccess = false
        self.savedStandalone = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.remoteID = nil
        self.syncStatus = .pending
    }
}
```

- [ ] **Step 4: Implement SchemaV1 + ModelContainerFactory**

```swift
// SciNapseKit/Sources/SciNapseKit/Models/SchemaV1.swift
import Foundation
import SwiftData

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Topic.self, Post.self, Source.self]
    }
}

public enum AppMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
```

```swift
// SciNapseKit/Sources/SciNapseKit/Persistence/ModelContainerFactory.swift
import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: config)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter ModelsTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add SciNapseKit
git commit -m "feat(kit): SwiftData models (Topic/Post/Source) + container factory"
```

---

### Task 4: Verification value types

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/Types.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/TypesTests.swift`

**Interfaces:**
- Consumes: enums (Task 2).
- Produces: `ResolvedMetadata`, `RetractionInfo` (+ `.none`), `OpenAccessInfo` (+ `.unknown`), `ParsedIdentifier`, `VerificationResult`, `protocol MetadataResolving` — assinaturas exatas no Shared Type Contracts.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/TypesTests.swift
import XCTest
@testable import SciNapseKit

final class TypesTests: XCTestCase {
    func test_retractionNone_andOAUnknown_constants() {
        XCTAssertEqual(RetractionInfo.none.status, .none)
        XCTAssertFalse(OpenAccessInfo.unknown.isOpenAccess)
    }
    func test_resolvedMetadata_isEquatable() {
        let a = ResolvedMetadata(title: "T", authors: ["X Y"])
        let b = ResolvedMetadata(title: "T", authors: ["X Y"])
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter TypesTests`
Expected: FAIL — "cannot find 'RetractionInfo'".

- [ ] **Step 3: Implement the types**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/Types.swift
import Foundation

public struct ResolvedMetadata: Sendable, Equatable {
    public var title: String?
    public var authors: [String]
    public var journal: String?
    public var year: Int?
    public var month: String?
    public var day: Int?
    public var volume: String?
    public var issue: String?
    public var pages: String?
    public var abstract: String?
    public var workType: String?
    public var doi: String?
    public var pmid: String?

    public init(title: String? = nil, authors: [String] = [], journal: String? = nil,
                year: Int? = nil, month: String? = nil, day: Int? = nil,
                volume: String? = nil, issue: String? = nil, pages: String? = nil,
                abstract: String? = nil, workType: String? = nil,
                doi: String? = nil, pmid: String? = nil) {
        self.title = title; self.authors = authors; self.journal = journal
        self.year = year; self.month = month; self.day = day
        self.volume = volume; self.issue = issue; self.pages = pages
        self.abstract = abstract; self.workType = workType; self.doi = doi; self.pmid = pmid
    }
}

public struct RetractionInfo: Sendable, Equatable {
    public var status: RetractionStatus
    public var date: Date?
    public var noticeDOI: String?
    public init(status: RetractionStatus, date: Date? = nil, noticeDOI: String? = nil) {
        self.status = status; self.date = date; self.noticeDOI = noticeDOI
    }
    public static let none = RetractionInfo(status: .none)
}

public struct OpenAccessInfo: Sendable, Equatable {
    public var isOpenAccess: Bool
    public var status: String?
    public var url: String?
    public init(isOpenAccess: Bool, status: String? = nil, url: String? = nil) {
        self.isOpenAccess = isOpenAccess; self.status = status; self.url = url
    }
    public static let unknown = OpenAccessInfo(isOpenAccess: false)
}

public enum ParsedIdentifier: Sendable, Equatable {
    case doi(String)
    case pmid(String)
    case url(URL)
    case unknown
}

public struct VerificationResult: Sendable, Equatable {
    public var metadata: ResolvedMetadata
    public var trustTier: TrustTier
    public var retraction: RetractionInfo
    public var openAccess: OpenAccessInfo
    public var resolvedURL: String?
    public init(metadata: ResolvedMetadata, trustTier: TrustTier,
                retraction: RetractionInfo = .none, openAccess: OpenAccessInfo = .unknown,
                resolvedURL: String? = nil) {
        self.metadata = metadata; self.trustTier = trustTier
        self.retraction = retraction; self.openAccess = openAccess; self.resolvedURL = resolvedURL
    }
}

public protocol MetadataResolving: Sendable {
    func verify(_ raw: String) async throws -> VerificationResult
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter TypesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): verification value types + MetadataResolving protocol"
```

---

### Task 5: IdentifierParser

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/IdentifierParser.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/IdentifierParserTests.swift`

**Interfaces:**
- Consumes: `ParsedIdentifier`, `SourceKind` (Tasks 2, 4).
- Produces: `enum IdentifierParser` com `static func parse(_ raw: String) -> ParsedIdentifier`, `static func extractDOI(in text: String) -> String?`, `static func extractPMID(in text: String) -> String?`, `static func kind(for raw: String) -> SourceKind`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/IdentifierParserTests.swift
import XCTest
@testable import SciNapseKit

final class IdentifierParserTests: XCTestCase {
    func test_bareDOI() {
        XCTAssertEqual(IdentifierParser.parse("10.1177/1758835920922055"), .doi("10.1177/1758835920922055"))
    }
    func test_doiURL_extractsDOI() {
        XCTAssertEqual(IdentifierParser.parse("https://doi.org/10.1038/nature12373"), .doi("10.1038/nature12373"))
    }
    func test_barePMID() {
        XCTAssertEqual(IdentifierParser.parse("33535474"), .pmid("33535474"))
    }
    func test_pubmedURL_extractsPMID() {
        XCTAssertEqual(IdentifierParser.parse("https://pubmed.ncbi.nlm.nih.gov/33535474/"), .pmid("33535474"))
    }
    func test_pmidWithLabel() {
        XCTAssertEqual(IdentifierParser.parse("PMID: 12345678"), .pmid("12345678"))
    }
    func test_arbitraryURL() {
        guard case .url(let u) = IdentifierParser.parse("https://www.who.int/news/item/abc") else {
            return XCTFail("esperava .url")
        }
        XCTAssertEqual(u.host, "www.who.int")
    }
    func test_garbage_isUnknown() {
        XCTAssertEqual(IdentifierParser.parse("isso não é nada"), .unknown)
    }
    func test_kind_mapsCorrectly() {
        XCTAssertEqual(IdentifierParser.kind(for: "10.1056/x"), .doi)
        XCTAssertEqual(IdentifierParser.kind(for: "123"), .pmid)
        XCTAssertEqual(IdentifierParser.kind(for: "https://x.com"), .url)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter IdentifierParserTests`
Expected: FAIL — "cannot find 'IdentifierParser'".

- [ ] **Step 3: Implement IdentifierParser**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/IdentifierParser.swift
import Foundation

public enum IdentifierParser {
    // Padrão canônico Crossref (case-insensitive). Removemos pontuação final no caller.
    private static let doiPattern = #"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+"#
    private static let pmidStrict = #"^[1-9]\d{0,7}$"#

    public static func parse(_ raw: String) -> ParsedIdentifier {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        // 1. DOI puro (string inteira é um DOI)
        if let doi = extractDOI(in: trimmed), trimmed.range(of: doiPattern, options: [.regularExpression, .caseInsensitive])?.lowerBound == trimmed.startIndex || trimmed.lowercased().hasPrefix("10.") {
            // string começa em "10." → trate como DOI puro
            if trimmed.lowercased().hasPrefix("10.") { return .doi(doi) }
        }
        // 2. PMID puro
        if trimmed.range(of: pmidStrict, options: .regularExpression) != nil {
            return .pmid(trimmed)
        }
        // 3. PMID rotulado ("PMID: 123")
        if let pmid = extractPMID(in: trimmed), !looksLikeURL(trimmed) {
            return .pmid(pmid)
        }
        // 4. URL
        if looksLikeURL(trimmed), let url = URL(string: trimmed) {
            return .url(url)
        }
        // 5. DOI embutido em texto livre
        if let doi = extractDOI(in: trimmed) { return .doi(doi) }
        return .unknown
    }

    public static func extractDOI(in text: String) -> String? {
        guard let range = text.range(of: doiPattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var doi = String(text[range])
        // Remove pontuação final capturada por engano
        while let last = doi.last, ".,;)\"'".contains(last) { doi.removeLast() }
        return doi
    }

    public static func extractPMID(in text: String) -> String? {
        // URL do PubMed
        if let r = text.range(of: #"pubmed\.ncbi\.nlm\.nih\.gov/([1-9]\d{0,7})"#, options: .regularExpression) {
            return text[r].split(separator: "/").last.map(String.init)
        }
        // "PMID: 123"
        if let r = text.range(of: #"(?i)PMID[:\s]+([1-9]\d{0,7})"#, options: .regularExpression) {
            return text[r].components(separatedBy: CharacterSet(charactersIn: ": ")).last
        }
        return nil
    }

    // NOTA: kind() deriva SEMPRE de parse() — sem casos especiais. Fixtures de
    // teste devem usar DOIs válidos (registrant de 4–9 dígitos), ex: "10.1056/x".
    public static func kind(for raw: String) -> SourceKind {
        switch parse(raw) {
        case .doi: return .doi
        case .pmid: return .pmid
        case .url, .unknown: return .url
        }
    }

    private static func looksLikeURL(_ s: String) -> Bool {
        s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter IdentifierParserTests`
Expected: PASS (8 tests). If `test_pubmedURL_extractsPMID` fails, confirm `extractPMID` strips the trailing `/`.

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): IdentifierParser (DOI/PMID/URL detection)"
```

---

### Task 6: DomainAllowlist

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/DomainAllowlist.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/DomainAllowlistTests.swift`

**Interfaces:**
- Produces: `enum DomainAllowlist` com `static let domains: Set<String>` e `static func isRecognized(_ url: URL) -> Bool`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/DomainAllowlistTests.swift
import XCTest
@testable import SciNapseKit

final class DomainAllowlistTests: XCTestCase {
    func test_recognizesExactDomain() {
        XCTAssertTrue(DomainAllowlist.isRecognized(URL(string: "https://www.who.int/news/x")!))
    }
    func test_recognizesSubdomain() {
        XCTAssertTrue(DomainAllowlist.isRecognized(URL(string: "https://academic.oup.com/article/1")!))
    }
    func test_rejectsRandomBlog() {
        XCTAssertFalse(DomainAllowlist.isRecognized(URL(string: "https://meublog.example.com/post")!))
    }
    func test_recognizesBrazilianGov() {
        XCTAssertTrue(DomainAllowlist.isRecognized(URL(string: "https://www.gov.br/anvisa/pt-br")!) ||
                      DomainAllowlist.isRecognized(URL(string: "https://anvisa.gov.br/x")!))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter DomainAllowlistTests`
Expected: FAIL — "cannot find 'DomainAllowlist'".

- [ ] **Step 3: Implement DomainAllowlist**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/DomainAllowlist.swift
import Foundation

public enum DomainAllowlist {
    public static let domains: Set<String> = [
        // Órgãos
        "nih.gov", "ncbi.nlm.nih.gov", "cdc.gov", "fda.gov", "who.int", "paho.org",
        "ema.europa.eu", "ecdc.europa.eu", "anvisa.gov.br", "saude.gov.br", "fiocruz.br",
        "scielo.br", "clinicaltrials.gov", "cochranelibrary.com", "europepmc.org",
        // Preprints / repositórios
        "medrxiv.org", "biorxiv.org", "arxiv.org", "researchsquare.com", "ssrn.com",
        "osf.io", "zenodo.org", "figshare.com",
        // Periódicos / editoras
        "nejm.org", "thelancet.com", "bmj.com", "jamanetwork.com", "nature.com",
        "science.org", "cell.com", "pnas.org", "springer.com", "link.springer.com",
        "wiley.com", "onlinelibrary.wiley.com", "sciencedirect.com", "academic.oup.com",
        "karger.com", "tandfonline.com", "mdpi.com", "frontiersin.org", "plos.org",
        "elifesciences.org",
        // Sociedades
        "ahajournals.org", "diabetesjournals.org", "atsjournals.org", "acpjournals.org",
        "annals.org", "ascopubs.org", "endocrine.org", "jci.org"
    ]

    public static func isRecognized(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
```

> Nota: `gov.br` é eTLD; o teste cobre `anvisa.gov.br` (subdomínio listado). Páginas em `www.gov.br/anvisa` casam por `gov.br`? Não — `gov.br` não está na lista por ser eTLD genérico. O teste usa `||` para aceitar a forma `anvisa.gov.br`. Mantemos só domínios específicos para evitar falso-positivo em qualquer `*.gov.br`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter DomainAllowlistTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): DomainAllowlist for recognized-source tier"
```

---

### Task 7: VancouverFormatter

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/VancouverFormatter.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/VancouverFormatterTests.swift`

**Interfaces:**
- Consumes: `ResolvedMetadata` (Task 4).
- Produces: `enum VancouverFormatter` com `static func format(_ m: ResolvedMetadata) -> String` e `static func abbreviatePages(start: String, end: String) -> String`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/VancouverFormatterTests.swift
import XCTest
@testable import SciNapseKit

final class VancouverFormatterTests: XCTestCase {
    func test_standardArticle() {
        let m = ResolvedMetadata(title: "Solid-organ transplantation in HIV-infected patients",
                                 authors: ["Halpern SD", "Ubel PA", "Caplan AL"],
                                 journal: "N Engl J Med", year: 2002, month: "Jul", day: 25,
                                 volume: "347", issue: "4", pages: "284-287",
                                 doi: "10.1056/nejm200207253470409")
        let out = VancouverFormatter.format(m)
        XCTAssertEqual(out, "Halpern SD, Ubel PA, Caplan AL. Solid-organ transplantation in HIV-infected patients. N Engl J Med. 2002 Jul 25;347(4):284-7. https://doi.org/10.1056/nejm200207253470409")
    }
    func test_sevenAuthors_etAl() {
        let authors = (1...7).map { "Author\($0) AB" }
        let m = ResolvedMetadata(title: "T", authors: authors, journal: "J", year: 2020)
        let out = VancouverFormatter.format(m)
        XCTAssertTrue(out.hasPrefix("Author1 AB, Author2 AB, Author3 AB, Author4 AB, Author5 AB, Author6 AB, et al."))
    }
    func test_noAuthor_startsWithTitle() {
        let m = ResolvedMetadata(title: "Anon report", authors: [], journal: "Health News", year: 2005)
        XCTAssertTrue(VancouverFormatter.format(m).hasPrefix("Anon report."))
    }
    func test_noVolume_pagesAfterColon() {
        let m = ResolvedMetadata(title: "T", authors: ["X Y"], journal: "J", year: 1995, pages: "5")
        XCTAssertTrue(VancouverFormatter.format(m).contains("1995:5."))
    }
    func test_abbreviatePages() {
        XCTAssertEqual(VancouverFormatter.abbreviatePages(start: "284", end: "287"), "7")
        XCTAssertEqual(VancouverFormatter.abbreviatePages(start: "1432", end: "1440"), "40")
        XCTAssertEqual(VancouverFormatter.abbreviatePages(start: "198", end: "204"), "204")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter VancouverFormatterTests`
Expected: FAIL — "cannot find 'VancouverFormatter'".

- [ ] **Step 3: Implement VancouverFormatter**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/VancouverFormatter.swift
import Foundation

public enum VancouverFormatter {
    public static func format(_ m: ResolvedMetadata) -> String {
        var parts: [String] = []

        // Autores
        if !m.authors.isEmpty {
            if m.authors.count <= 6 {
                parts.append(m.authors.joined(separator: ", ") + ".")
            } else {
                parts.append(m.authors.prefix(6).joined(separator: ", ") + ", et al.")
            }
        }
        // Título
        if let title = m.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            parts.append(title.hasSuffix(".") ? title : title + ".")
        }
        // Journal
        if let j = m.journal, !j.isEmpty { parts.append(j + ".") }

        // Data + localização (vol/issue/páginas)
        var dateStr = m.year.map { String($0) } ?? ""
        if let mo = m.month { dateStr += " \(mo)" }
        if let d = m.day { dateStr += " \(d)" }

        var loc = ""
        if let vol = m.volume {
            loc += vol
            if let iss = m.issue { loc += "(\(iss))" }
            if let pages = m.pages { loc += ":" + formatPages(pages) }
        } else if let pages = m.pages {
            loc += ":" + formatPages(pages)
        }
        if !dateStr.isEmpty || !loc.isEmpty {
            parts.append(dateStr + (loc.isEmpty ? "" : ";\(loc)") + ".")
        }
        // DOI
        if let doi = m.doi { parts.append("https://doi.org/\(doi)") }

        return parts.joined(separator: " ")
    }

    /// "284-287" -> "284-7". Mantém e-location IDs (ex.: "e202301234") intactos.
    private static func formatPages(_ pages: String) -> String {
        let comps = pages.split(separator: "-", maxSplits: 1).map(String.init)
        guard comps.count == 2 else { return pages }
        return comps[0] + "-" + abbreviatePages(start: comps[0], end: comps[1])
    }

    public static func abbreviatePages(start: String, end: String) -> String {
        guard start.count == end.count, start.allSatisfy(\.isNumber), end.allSatisfy(\.isNumber) else {
            return end
        }
        let s = Array(start), e = Array(end)
        var i = 0
        while i < e.count && s[i] == e[i] { i += 1 }
        return i == 0 ? end : String(e[i...])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter VancouverFormatterTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): VancouverFormatter with page abbreviation"
```

---

### Task 8: AbstractReconstructor

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/AbstractReconstructor.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/AbstractReconstructorTests.swift`

**Interfaces:**
- Produces: `enum AbstractReconstructor` com `static func reconstruct(_ index: [String: [Int]]?) -> String?`.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter AbstractReconstructorTests`
Expected: FAIL — "cannot find 'AbstractReconstructor'".

- [ ] **Step 3: Implement AbstractReconstructor**

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter AbstractReconstructorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): AbstractReconstructor (OpenAlex inverted index)"
```

---

### Task 9: HTTPClient + StubURLProtocol

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/HTTPClient.swift`
- Create: `SciNapseKit/Tests/SciNapseKitTests/Support/StubURLProtocol.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/HTTPClientTests.swift`

**Interfaces:**
- Consumes: `AppError` (Task 1).
- Produces: `struct HTTPResponse: Sendable`, `protocol HTTPClient: Sendable`, `final class LiveHTTPClient: HTTPClient` com `init(session: URLSession = .shared, maxRetries: Int = 3)`.
- Produces (test support): `final class StubURLProtocol: URLProtocol` com `static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?` e `static func session() -> URLSession`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/HTTPClientTests.swift
import XCTest
@testable import SciNapseKit

final class HTTPClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func test_get_returnsBodyAndStatus() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("hello".utf8))
        }
        let client = LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0)
        let r = try await client.get(URL(string: "https://x.test/a")!, headers: ["User-Agent": "T"])
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(String(decoding: r.data, as: UTF8.self), "hello")
    }

    func test_get_forwardsHeaders() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), "SciNapse/1.0")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let client = LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0)
        _ = try await client.get(URL(string: "https://x.test")!, headers: ["User-Agent": "SciNapse/1.0"])
    }
}
```

- [ ] **Step 2: Create StubURLProtocol support**

```swift
// SciNapseKit/Tests/SciNapseKitTests/Support/StubURLProtocol.swift
import Foundation

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter HTTPClientTests`
Expected: FAIL — "cannot find 'LiveHTTPClient'".

- [ ] **Step 4: Implement HTTPClient**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/HTTPClient.swift
import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let finalURL: URL?
}

public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public final class LiveHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let maxRetries: Int

    public init(session: URLSession = .shared, maxRetries: Int = 3) {
        self.session = session
        self.maxRetries = maxRetries
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var attempt = 0
        while true {
            var req = URLRequest(url: url, timeoutInterval: 10)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw AppError.invalidResponse }
                if (http.statusCode == 429 || http.statusCode >= 500), attempt < maxRetries {
                    attempt += 1
                    let backoff = pow(2.0, Double(attempt)) * 0.2 + Double.random(in: 0...0.2)
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    continue
                }
                return HTTPResponse(data: data, status: http.statusCode, finalURL: http.url)
            } catch let urlError as URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                    throw AppError.offline
                default:
                    // timeout e demais erros: tenta de novo enquanto houver retries; senão repropaga o URLError
                    if attempt < maxRetries { attempt += 1; continue }
                    throw urlError
                }
            }
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter HTTPClientTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): HTTPClient with backoff + StubURLProtocol test support"
```

---

### Task 10: CrossrefClient (metadados + retração)

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/CrossrefClient.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/CrossrefClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `ResolvedMetadata`, `RetractionInfo`, `AppError`, `Config`.
- Produces: `struct CrossrefClient: Sendable` com `init(http: HTTPClient)` e `func fetch(doi: String) async throws -> (ResolvedMetadata, RetractionInfo)`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/CrossrefClientTests.swift
import XCTest
@testable import SciNapseKit

final class CrossrefClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    private func stub(_ json: String, status: Int = 200) {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
    }

    func test_parsesMetadata() async throws {
        stub(#"""
        {"status":"ok","message":{"DOI":"10.1056/x","title":["Solid-organ transplantation"],
        "container-title":["N Engl J Med"],"type":"journal-article",
        "issued":{"date-parts":[[2002,7,25]]},"volume":"347","issue":"4","page":"284-287",
        "author":[{"given":"Samuel D.","family":"Halpern","sequence":"first"}]}}
        """#)
        let client = CrossrefClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let (meta, retraction) = try await client.fetch(doi: "10.1056/x")
        XCTAssertEqual(meta.title, "Solid-organ transplantation")
        XCTAssertEqual(meta.journal, "N Engl J Med")
        XCTAssertEqual(meta.year, 2002)
        XCTAssertEqual(meta.authors, ["Halpern SD"])
        XCTAssertEqual(meta.volume, "347")
        XCTAssertEqual(retraction.status, .none)
    }

    func test_detectsRetraction() async throws {
        stub(#"""
        {"status":"ok","message":{"DOI":"10.1177/1758835920922055","title":["RETRACTED: Myc"],
        "container-title":["X"],"issued":{"date-parts":[[2020,5,1]]},
        "updated-by":[{"DOI":"10.1/notice","type":"retraction","label":"Retraction",
        "source":"retraction-watch","updated":{"date-parts":[[2023,4,22]]}},
        {"DOI":"10.1/notice","type":"retraction","label":"Retraction","source":"publisher",
        "updated":{"date-parts":[[2023,4,22]]}}]}}
        """#)
        let client = CrossrefClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let (_, retraction) = try await client.fetch(doi: "10.1177/1758835920922055")
        XCTAssertEqual(retraction.status, .retracted)
        XCTAssertEqual(retraction.noticeDOI, "10.1/notice")
    }

    func test_throwsNotFoundOn404() async {
        stub("Resource not found.", status: 404)
        let client = CrossrefClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        do { _ = try await client.fetch(doi: "10.9999/missing"); XCTFail("esperava erro") }
        catch { XCTAssertEqual(error as? AppError, .notFound) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter CrossrefClientTests`
Expected: FAIL — "cannot find 'CrossrefClient'".

- [ ] **Step 3: Implement CrossrefClient**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/CrossrefClient.swift
import Foundation

public struct CrossrefClient: Sendable {
    private let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    private struct Envelope: Decodable { let message: Message }
    private struct Message: Decodable {
        let DOI: String?
        let title: [String]?
        let containerTitle: [String]?
        let type: String?
        let volume: String?
        let issue: String?
        let page: String?
        let abstract: String?
        let author: [Author]?
        let issued: DateParts?
        let publishedPrint: DateParts?
        let publishedOnline: DateParts?
        let updatedBy: [Update]?
        enum CodingKeys: String, CodingKey {
            case DOI, title, type, volume, issue, page, abstract, author, issued
            case containerTitle = "container-title"
            case publishedPrint = "published-print"
            case publishedOnline = "published-online"
            case updatedBy = "updated-by"
        }
    }
    private struct Author: Decodable { let given: String?; let family: String? }
    private struct DateParts: Decodable { let dateParts: [[Int]]?; enum CodingKeys: String, CodingKey { case dateParts = "date-parts" } }
    private struct Update: Decodable { let DOI: String?; let type: String?; let updated: DateParts? }

    public func fetch(doi: String) async throws -> (ResolvedMetadata, RetractionInfo) {
        guard let url = URL(string: "https://api.crossref.org/v1/works/\(doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi)") else { throw AppError.invalidResponse }
        let resp = try await http.get(url, headers: ["User-Agent": Config.userAgent])
        guard resp.status != 404 else { throw AppError.notFound }
        guard resp.status == 200 else { throw AppError.invalidResponse }
        let decoder = JSONDecoder()
        let msg = try decoder.decode(Envelope.self, from: resp.data).message

        var meta = ResolvedMetadata()
        meta.doi = msg.DOI
        meta.title = msg.title?.first.map(stripRetractedPrefix)
        meta.journal = msg.containerTitle?.first
        meta.workType = msg.type
        meta.volume = msg.volume
        meta.issue = msg.issue
        meta.pages = msg.page
        meta.abstract = msg.abstract.map(stripJATS)
        meta.authors = (msg.author ?? []).compactMap(formatAuthor)
        let dp = (msg.issued ?? msg.publishedPrint ?? msg.publishedOnline)?.dateParts?.first
        meta.year = dp?.first
        if let dp, dp.count > 1 { meta.month = monthAbbrev(dp[1]) }
        if let dp, dp.count > 2 { meta.day = dp[2] }

        let retraction = parseRetraction(msg.updatedBy, titleHadPrefix: msg.title?.first?.uppercased().hasPrefix("RETRACTED:") ?? false)
        return (meta, retraction)
    }

    private func formatAuthor(_ a: Author) -> String? {
        guard let family = a.family else { return a.given }
        let initials = (a.given ?? "")
            .components(separatedBy: CharacterSet(charactersIn: " .-"))
            .compactMap { $0.first.map(String.init) }
            .prefix(2)
            .joined()
        return initials.isEmpty ? family : "\(family) \(initials)"
    }

    private func parseRetraction(_ updates: [Update]?, titleHadPrefix: Bool) -> RetractionInfo {
        guard let updates, !updates.isEmpty else {
            return titleHadPrefix ? RetractionInfo(status: .retracted) : .none
        }
        // Prioridade: retraction > concern > correction. Deduplica por DOI do aviso.
        func date(_ u: Update) -> Date? {
            guard let y = u.updated?.dateParts?.first?.first else { return nil }
            return Calendar(identifier: .gregorian).date(from: DateComponents(year: y))
        }
        if let u = updates.first(where: { $0.type == "retraction" }) {
            return RetractionInfo(status: .retracted, date: date(u), noticeDOI: u.DOI)
        }
        if let u = updates.first(where: { $0.type == "expression_of_concern" }) {
            return RetractionInfo(status: .concern, date: date(u), noticeDOI: u.DOI)
        }
        if let u = updates.first(where: { $0.type == "correction" }) {
            return RetractionInfo(status: .correction, date: date(u), noticeDOI: u.DOI)
        }
        return .none
    }

    private func stripRetractedPrefix(_ t: String) -> String {
        let upper = t.uppercased()
        if upper.hasPrefix("RETRACTED:") { return String(t.dropFirst("RETRACTED:".count)).trimmingCharacters(in: .whitespaces) }
        return t
    }
    private func stripJATS(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func monthAbbrev(_ m: Int) -> String? {
        let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return (1...12).contains(m) ? names[m-1] : nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter CrossrefClientTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): CrossrefClient (metadata + retraction detection)"
```

---

### Task 11: UnpaywallClient (open access)

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/UnpaywallClient.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/UnpaywallClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `OpenAccessInfo`, `Config`.
- Produces: `struct UnpaywallClient: Sendable` com `init(http: HTTPClient)` e `func fetch(doi: String) async -> OpenAccessInfo` (best-effort: nunca lança; falha → `.unknown`).

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/UnpaywallClientTests.swift
import XCTest
@testable import SciNapseKit

final class UnpaywallClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func test_parsesOpenAccess() async {
        StubURLProtocol.handler = { req in
            let json = #"{"is_oa":true,"oa_status":"gold","best_oa_location":{"url":"https://x/pdf","url_for_pdf":"https://x/pdf"}}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let client = UnpaywallClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let oa = await client.fetch(doi: "10.1056/x")
        XCTAssertTrue(oa.isOpenAccess)
        XCTAssertEqual(oa.status, "gold")
        XCTAssertEqual(oa.url, "https://x/pdf")
    }

    func test_404_returnsUnknown() async {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data("<h1>Not Found</h1>".utf8))
        }
        let client = UnpaywallClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let oa = await client.fetch(doi: "10.9999/missing")
        XCTAssertFalse(oa.isOpenAccess)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter UnpaywallClientTests`
Expected: FAIL — "cannot find 'UnpaywallClient'".

- [ ] **Step 3: Implement UnpaywallClient**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/UnpaywallClient.swift
import Foundation

public struct UnpaywallClient: Sendable {
    private let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    private struct Payload: Decodable {
        let isOA: Bool?
        let oaStatus: String?
        let bestOaLocation: Location?
        enum CodingKeys: String, CodingKey {
            case isOA = "is_oa", oaStatus = "oa_status", bestOaLocation = "best_oa_location"
        }
    }
    private struct Location: Decodable {
        let url: String?
        let urlForPdf: String?
        let urlForLandingPage: String?
        enum CodingKeys: String, CodingKey {
            case url, urlForPdf = "url_for_pdf", urlForLandingPage = "url_for_landing_page"
        }
    }

    public func fetch(doi: String) async -> OpenAccessInfo {
        let email = Config.contactEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Config.contactEmail
        guard let url = URL(string: "https://api.unpaywall.org/v2/\(doi)?email=\(email)") else { return .unknown }
        guard let resp = try? await http.get(url, headers: [:]), resp.status == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: resp.data) else {
            return .unknown
        }
        let bestURL = payload.bestOaLocation?.urlForPdf
            ?? payload.bestOaLocation?.urlForLandingPage
            ?? payload.bestOaLocation?.url
        return OpenAccessInfo(isOpenAccess: payload.isOA ?? false, status: payload.oaStatus, url: bestURL)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter UnpaywallClientTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): UnpaywallClient (open access, best-effort)"
```

---

### Task 12: PubMedClient (PMID → DOI / metadados)

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/PubMedClient.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/PubMedClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `ResolvedMetadata`, `Config`.
- Produces: `struct PubMedClient: Sendable` com `init(http: HTTPClient)`, `func resolveDOI(pmid: String) async -> String?`, `func fetchSummary(pmid: String) async throws -> ResolvedMetadata`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/PubMedClientTests.swift
import XCTest
@testable import SciNapseKit

final class PubMedClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func test_resolveDOI_fromConverter() async {
        StubURLProtocol.handler = { req in
            let json = #"{"status":"ok","records":[{"pmid":"33535474","doi":"10.3390/ijerph18031290"}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let client = PubMedClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let doi = await client.resolveDOI(pmid: "33535474")
        XCTAssertEqual(doi, "10.3390/ijerph18031290")
    }

    func test_fetchSummary_parsesMetadata() async throws {
        StubURLProtocol.handler = { req in
            let json = #"""
            {"result":{"33535474":{"uid":"33535474","title":"BRAINballs Program.",
            "fulljournalname":"Int J Environ Res Public Health","pubdate":"2021 Feb 1",
            "volume":"18","issue":"3","pages":"1290",
            "authors":[{"name":"Pham VH"},{"name":"Tran TN"}],
            "articleids":[{"idtype":"doi","value":"10.3390/ijerph18031290"}]},"uids":["33535474"]}}
            """#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let client = PubMedClient(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let meta = try await client.fetchSummary(pmid: "33535474")
        XCTAssertEqual(meta.title, "BRAINballs Program.")
        XCTAssertEqual(meta.journal, "Int J Environ Res Public Health")
        XCTAssertEqual(meta.year, 2021)
        XCTAssertEqual(meta.authors, ["Pham VH", "Tran TN"])
        XCTAssertEqual(meta.doi, "10.3390/ijerph18031290")
        XCTAssertEqual(meta.pmid, "33535474")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter PubMedClientTests`
Expected: FAIL — "cannot find 'PubMedClient'".

- [ ] **Step 3: Implement PubMedClient**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/PubMedClient.swift
import Foundation

public struct PubMedClient: Sendable {
    private let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    private var qs: String { "tool=\(Config.pubmedTool)&email=\(Config.contactEmail)" }

    // MARK: PMID -> DOI via PMC ID Converter
    private struct ConverterResponse: Decodable { let records: [Record]? }
    private struct Record: Decodable { let pmid: String?; let doi: String? }

    public func resolveDOI(pmid: String) async -> String? {
        let urlStr = "https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/?ids=\(pmid)&idtype=pmid&format=json&\(qs)"
        guard let url = URL(string: urlStr),
              let resp = try? await http.get(url, headers: [:]), resp.status == 200,
              let decoded = try? JSONDecoder().decode(ConverterResponse.self, from: resp.data) else { return nil }
        return decoded.records?.first?.doi
    }

    // MARK: ESummary (JSON) -> metadados
    public func fetchSummary(pmid: String) async throws -> ResolvedMetadata {
        let urlStr = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=\(pmid)&retmode=json&\(qs)"
        guard let url = URL(string: urlStr) else { throw AppError.unresolvable }
        let resp = try await http.get(url, headers: [:])
        guard resp.status == 200 else { throw AppError.invalidResponse }

        // result é um dicionário com a chave do PMID + "uids"; decodificamos manualmente.
        guard let root = try JSONSerialization.jsonObject(with: resp.data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let entry = result[pmid] as? [String: Any] else {
            throw AppError.notFound
        }
        var meta = ResolvedMetadata()
        meta.pmid = pmid
        meta.title = entry["title"] as? String
        meta.journal = entry["fulljournalname"] as? String
        meta.volume = entry["volume"] as? String
        meta.issue = entry["issue"] as? String
        meta.pages = entry["pages"] as? String
        if let pubdate = entry["pubdate"] as? String,
           let yearStr = pubdate.split(separator: " ").first, let y = Int(yearStr) {
            meta.year = y
        }
        if let authors = entry["authors"] as? [[String: Any]] {
            meta.authors = authors.compactMap { $0["name"] as? String }
        }
        if let ids = entry["articleids"] as? [[String: Any]] {
            meta.doi = ids.first(where: { ($0["idtype"] as? String) == "doi" })?["value"] as? String
        }
        return meta
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter PubMedClientTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): PubMedClient (PMC ID converter + esummary)"
```

---

### Task 13: HTMLDoiExtractor

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/HTMLDoiExtractor.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/HTMLDoiExtractorTests.swift`

**Interfaces:**
- Consumes: `IdentifierParser` (Task 5).
- Produces: `enum HTMLDoiExtractor` com `static func extractDOI(fromHTML html: String) -> String?` e `static func extractTitle(fromHTML html: String) -> String?`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/HTMLDoiExtractorTests.swift
import XCTest
@testable import SciNapseKit

final class HTMLDoiExtractorTests: XCTestCase {
    func test_citationDoiMeta() {
        let html = #"<html><head><meta name="citation_doi" content="10.1038/nature12373"><title>X</title></head></html>"#
        XCTAssertEqual(HTMLDoiExtractor.extractDOI(fromHTML: html), "10.1038/nature12373")
    }
    func test_dcIdentifierWithURL() {
        let html = #"<meta name="DC.identifier" content="https://doi.org/10.1056/abc">"#
        XCTAssertEqual(HTMLDoiExtractor.extractDOI(fromHTML: html), "10.1056/abc")
    }
    func test_jsonLD() {
        let html = #"<script type="application/ld+json">{"@type":"ScholarlyArticle","identifier":{"propertyID":"doi","value":"10.7717/zzz"}}</script>"#
        XCTAssertEqual(HTMLDoiExtractor.extractDOI(fromHTML: html), "10.7717/zzz")
    }
    func test_noDOI() {
        XCTAssertNil(HTMLDoiExtractor.extractDOI(fromHTML: "<html>nada</html>"))
    }
    func test_title() {
        XCTAssertEqual(HTMLDoiExtractor.extractTitle(fromHTML: "<title>Meu Artigo</title>"), "Meu Artigo")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter HTMLDoiExtractorTests`
Expected: FAIL — "cannot find 'HTMLDoiExtractor'".

- [ ] **Step 3: Implement HTMLDoiExtractor**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/HTMLDoiExtractor.swift
import Foundation

public enum HTMLDoiExtractor {
    private static let metaNames = ["citation_doi", "dc.identifier", "prism.doi", "bepress_citation_doi"]

    public static func extractDOI(fromHTML html: String) -> String? {
        // 1. <meta name="citation_doi" content="...">  (case-insensitive no name)
        for match in metaTags(in: html) {
            if metaNames.contains(match.name.lowercased()), let doi = IdentifierParser.extractDOI(in: match.content) {
                return doi
            }
        }
        // 2. Qualquer DOI no HTML (fallback — JSON-LD, links doi.org, etc.)
        return IdentifierParser.extractDOI(in: html)
    }

    public static func extractTitle(fromHTML html: String) -> String? {
        guard let r = html.range(of: #"(?is)<title[^>]*>(.*?)</title>"#, options: .regularExpression) else { return nil }
        let inner = String(html[r])
            .replacingOccurrences(of: #"(?is)</?title[^>]*>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    private struct Meta { let name: String; let content: String }
    private static func metaTags(in html: String) -> [Meta] {
        var result: [Meta] = []
        let pattern = #"(?is)<meta\s+[^>]*?name=["']([^"']+)["'][^>]*?content=["']([^"']*)["'][^>]*?>"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let ns = html as NSString
        regex?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 3 else { return }
            result.append(Meta(name: ns.substring(with: m.range(at: 1)), content: ns.substring(with: m.range(at: 2))))
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter HTMLDoiExtractorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): HTMLDoiExtractor (meta tags + JSON-LD fallback)"
```

---

### Task 14: TrustClassifier

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/TrustClassifier.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/TrustClassifierTests.swift`

**Interfaces:**
- Consumes: `TrustTier`, `ParsedIdentifier`, `DomainAllowlist`.
- Produces: `enum TrustClassifier` com `static func tier(resolvedIdentifier: Bool, url: URL?) -> TrustTier`.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/TrustClassifierTests.swift
import XCTest
@testable import SciNapseKit

final class TrustClassifierTests: XCTestCase {
    func test_resolvedIdentifier_isVerified() {
        XCTAssertEqual(TrustClassifier.tier(resolvedIdentifier: true, url: nil), .verified)
    }
    func test_recognizedDomain_isRecognized() {
        XCTAssertEqual(TrustClassifier.tier(resolvedIdentifier: false, url: URL(string: "https://who.int/x")!), .recognized)
    }
    func test_unknownDomain_isUnverified() {
        XCTAssertEqual(TrustClassifier.tier(resolvedIdentifier: false, url: URL(string: "https://blog.example.com")!), .unverified)
    }
    func test_noURL_noIdentifier_isUnverified() {
        XCTAssertEqual(TrustClassifier.tier(resolvedIdentifier: false, url: nil), .unverified)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter TrustClassifierTests`
Expected: FAIL — "cannot find 'TrustClassifier'".

- [ ] **Step 3: Implement TrustClassifier**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/TrustClassifier.swift
import Foundation

public enum TrustClassifier {
    public static func tier(resolvedIdentifier: Bool, url: URL?) -> TrustTier {
        if resolvedIdentifier { return .verified }
        if let url, DomainAllowlist.isRecognized(url) { return .recognized }
        return .unverified
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter TrustClassifierTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): TrustClassifier (tier decision)"
```

---

### Task 15: MetadataService (orquestrador)

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Verification/MetadataService.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/MetadataServiceTests.swift`

**Interfaces:**
- Consumes: todos os clients + `IdentifierParser`, `TrustClassifier`, `VancouverFormatter`, `MetadataResolving`, `AppError`.
- Produces: `struct MetadataService: MetadataResolving` com `init(http: HTTPClient = LiveHTTPClient())` e `func verify(_ raw: String) async throws -> VerificationResult`. Preenche `metadata.abstract`/citação não aqui (citação é montada no `SourceFetcher`). Lança `AppError.offline` quando sem rede.

- [ ] **Step 1: Write the failing test**

```swift
// SciNapseKit/Tests/SciNapseKitTests/MetadataServiceTests.swift
import XCTest
@testable import SciNapseKit

final class MetadataServiceTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func test_doi_resolvesVerified() async throws {
        StubURLProtocol.handler = { req in
            let host = req.url!.host ?? ""
            let json: String
            if host.contains("crossref") {
                json = #"{"status":"ok","message":{"DOI":"10.1056/x","title":["T"],"container-title":["J"],"issued":{"date-parts":[[2020]]},"author":[{"given":"A","family":"Bee"}]}}"#
            } else { // unpaywall
                json = #"{"is_oa":false,"oa_status":"closed","best_oa_location":null}"#
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let service = MetadataService(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let result = try await service.verify("10.1056/x")
        XCTAssertEqual(result.trustTier, .verified)
        XCTAssertEqual(result.metadata.title, "T")
        XCTAssertEqual(result.metadata.authors, ["Bee A"])
    }

    func test_recognizedURL_withoutDOI() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("<html><title>OMS</title>sem doi aqui</html>".utf8))
        }
        let service = MetadataService(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let result = try await service.verify("https://www.who.int/news/item/x")
        XCTAssertEqual(result.trustTier, .recognized)
    }

    func test_unknownURL_isUnverified() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("<html>nada</html>".utf8))
        }
        let service = MetadataService(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        let result = try await service.verify("https://blog.example.com/post")
        XCTAssertEqual(result.trustTier, .unverified)
    }

    func test_offline_throws() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let service = MetadataService(http: LiveHTTPClient(session: StubURLProtocol.session(), maxRetries: 0))
        do { _ = try await service.verify("10.1056/x"); XCTFail("esperava offline") }
        catch { XCTAssertEqual(error as? AppError, .offline) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter MetadataServiceTests`
Expected: FAIL — "cannot find 'MetadataService'".

- [ ] **Step 3: Implement MetadataService**

```swift
// SciNapseKit/Sources/SciNapseKit/Verification/MetadataService.swift
import Foundation

public struct MetadataService: MetadataResolving {
    private let http: HTTPClient
    private let crossref: CrossrefClient
    private let unpaywall: UnpaywallClient
    private let pubmed: PubMedClient

    public init(http: HTTPClient = LiveHTTPClient()) {
        self.http = http
        self.crossref = CrossrefClient(http: http)
        self.unpaywall = UnpaywallClient(http: http)
        self.pubmed = PubMedClient(http: http)
    }

    public func verify(_ raw: String) async throws -> VerificationResult {
        switch IdentifierParser.parse(raw) {
        case .doi(let doi):
            return try await verifyDOI(doi, resolvedURL: "https://doi.org/\(doi)")
        case .pmid(let pmid):
            return try await verifyPMID(pmid)
        case .url(let url):
            return try await verifyURL(url)
        case .unknown:
            return VerificationResult(metadata: ResolvedMetadata(), trustTier: .unverified, resolvedURL: raw)
        }
    }

    private func verifyDOI(_ doi: String, resolvedURL: String?) async throws -> VerificationResult {
        let (meta, retraction) = try await crossref.fetch(doi: doi)
        let oa = await unpaywall.fetch(doi: doi)
        return VerificationResult(metadata: meta, trustTier: .verified, retraction: retraction,
                                  openAccess: oa, resolvedURL: resolvedURL)
    }

    private func verifyPMID(_ pmid: String) async throws -> VerificationResult {
        if let doi = await pubmed.resolveDOI(pmid: pmid) {
            return try await verifyDOI(doi, resolvedURL: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")
        }
        let meta = try await pubmed.fetchSummary(pmid: pmid)
        return VerificationResult(metadata: meta, trustTier: .verified,
                                  resolvedURL: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")
    }

    private func verifyURL(_ url: URL) async throws -> VerificationResult {
        // DOI no path?
        if let doi = IdentifierParser.extractDOI(in: url.absoluteString) {
            return try await verifyDOI(doi, resolvedURL: url.absoluteString)
        }
        // URL do PubMed?
        if let pmid = IdentifierParser.extractPMID(in: url.absoluteString) {
            return try await verifyPMID(pmid)
        }
        // Buscar HTML e procurar DOI nas meta tags
        let resp = try await http.get(url, headers: ["User-Agent": Config.userAgent])
        let finalURL = resp.finalURL ?? url
        if resp.status == 200 {
            let html = String(decoding: resp.data, as: UTF8.self)
            if let doi = HTMLDoiExtractor.extractDOI(fromHTML: html) {
                return try await verifyDOI(doi, resolvedURL: finalURL.absoluteString)
            }
            var meta = ResolvedMetadata()
            meta.title = HTMLDoiExtractor.extractTitle(fromHTML: html)
            let tier = TrustClassifier.tier(resolvedIdentifier: false, url: finalURL)
            return VerificationResult(metadata: meta, trustTier: tier, resolvedURL: finalURL.absoluteString)
        }
        let tier = TrustClassifier.tier(resolvedIdentifier: false, url: finalURL)
        return VerificationResult(metadata: ResolvedMetadata(), trustTier: tier, resolvedURL: finalURL.absoluteString)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter MetadataServiceTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): MetadataService pipeline (DOI/PMID/URL orchestration)"
```

---

### Task 16: SourceFetcher (@ModelActor)

**Files:**
- Create: `SciNapseKit/Sources/SciNapseKit/Persistence/SourceFetcher.swift`
- Test: `SciNapseKit/Tests/SciNapseKitTests/SourceFetcherTests.swift`

**Interfaces:**
- Consumes: `Source`, `Topic`, `Post`, `MetadataResolving`, `VerificationResult`, `VancouverFormatter`, `AppError`, `IdentifierParser`.
- Produces: `@ModelActor actor SourceFetcher` com:
  - `func addSource(rawInput: String, topicID: PersistentIdentifier?, postID: PersistentIdentifier?, savedStandalone: Bool, using service: any MetadataResolving) async -> PersistentIdentifier`
  - `func reverify(sourceID: PersistentIdentifier, using service: any MetadataResolving) async`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapseKit && swift test --filter SourceFetcherTests`
Expected: FAIL — "cannot find 'SourceFetcher'".

- [ ] **Step 3: Implement SourceFetcher**

```swift
// SciNapseKit/Sources/SciNapseKit/Persistence/SourceFetcher.swift
import Foundation
import SwiftData

@ModelActor
public actor SourceFetcher {
    public func addSource(rawInput: String,
                          topicID: PersistentIdentifier?,
                          postID: PersistentIdentifier?,
                          savedStandalone: Bool,
                          using service: any MetadataResolving) async -> PersistentIdentifier {
        let source = Source(rawInput: rawInput, kind: IdentifierParser.kind(for: rawInput))
        source.savedStandalone = savedStandalone
        if let topicID, let topic = self[topicID, as: Topic.self] { source.topic = topic }
        modelContext.insert(source)
        if let postID, let post = self[postID, as: Post.self] { post.sources.append(source) }

        await resolve(source: source, rawInput: rawInput, using: service)
        try? modelContext.save()
        return source.persistentModelID
    }

    public func reverify(sourceID: PersistentIdentifier, using service: any MetadataResolving) async {
        guard let source = self[sourceID, as: Source.self] else { return }
        await resolve(source: source, rawInput: source.rawInput, using: service)
        try? modelContext.save()
    }

    private func resolve(source: Source, rawInput: String, using service: any MetadataResolving) async {
        do {
            let r = try await service.verify(rawInput)
            apply(r, to: source)
            source.verificationState = .completed
        } catch AppError.offline {
            source.trustTier = .unverified
            source.verificationState = .pending
        } catch {
            source.trustTier = .unverified
            source.verificationState = .failed
        }
        source.updatedAt = Date()
    }

    private func apply(_ r: VerificationResult, to s: Source) {
        let m = r.metadata
        s.normalizedDOI = m.doi
        s.pmid = m.pmid
        s.resolvedURL = r.resolvedURL
        s.title = m.title
        s.authors = m.authors
        s.journal = m.journal
        s.year = m.year
        s.month = m.month
        s.day = m.day
        s.volume = m.volume
        s.issue = m.issue
        s.pages = m.pages
        s.abstract = m.abstract
        s.workType = m.workType
        s.trustTier = r.trustTier
        s.retractionStatus = r.retraction.status
        s.retractionDate = r.retraction.date
        s.retractionNoticeDOI = r.retraction.noticeDOI
        s.isOpenAccess = r.openAccess.isOpenAccess
        s.oaStatus = r.openAccess.status
        s.oaURL = r.openAccess.url
        s.fetchedAt = Date()
        // Citação Vancouver só quando há metadados suficientes
        if m.title != nil || !m.authors.isEmpty {
            s.formattedCitation = VancouverFormatter.format(m)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapseKit && swift test --filter SourceFetcherTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the FULL suite**

Run: `cd SciNapseKit && swift test`
Expected: PASS — todas as suites verdes (Scaffold, Enums, Models, Types, IdentifierParser, DomainAllowlist, Vancouver, AbstractReconstructor, HTTPClient, Crossref, Unpaywall, PubMed, HTMLDoiExtractor, TrustClassifier, MetadataService, SourceFetcher).

- [ ] **Step 6: Commit**

```bash
git add SciNapseKit && git commit -m "feat(kit): SourceFetcher @ModelActor (verify + persist, offline-aware)"
```

---

## Self-Review (preenchido)

**Spec coverage:** modelo de dados §5 → Tasks 2–3; motor de verificação §6 (parsing, Crossref primário, Unpaywall, PubMed, allowlist, retração, camadas) → Tasks 5–15; Vancouver §7 → Task 7; persistência offline-first §6.6 → Task 16. UI §9, digest §8 e sharing §8 ficam no **Plano 2** (app). OpenAlex opcional §6.2 → `AbstractReconstructor` (Task 8) + `Config.openAlexAPIKey` pronto; cliente OpenAlex completo é fast-follow (Fase 1.5) e não bloqueia nenhum AC.

**Placeholder scan:** nenhum TODO/“tratar erros”/“similar a”. Todos os steps têm código completo e comandos com saída esperada.

**Type consistency:** assinaturas batem com o Shared Type Contracts — `CrossrefClient.fetch -> (ResolvedMetadata, RetractionInfo)`, `UnpaywallClient.fetch -> OpenAccessInfo`, `PubMedClient.{resolveDOI,fetchSummary}`, `MetadataService.verify -> VerificationResult`, `SourceFetcher.addSource/reverify`. `VerificationResult`/`ResolvedMetadata` usados de forma idêntica em Tasks 4, 15, 16.

> **Nota de cobertura (sem cap silencioso):** o cliente OpenAlex de enriquecimento e o EFetch/XML do PubMed (abstract) não entram neste plano — são Fase 1.5. O abstract na Fase 1 vem do Crossref quando presente; ausência de abstract é aceitável e não falha nenhum AC.
