# SciNapse (App iOS) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Prereq:** O plano `2026-06-28-scinapse-fase1-engine.md` (SciNapseKit) deve estar concluído e com `swift test` verde.

**Goal:** Construir o app SwiftUI **SciNapse** sobre o `SciNapseKit`: tópicos, posts com gate de publicação, sheet de adicionar/verificar fonte com badges + alerta de retratação, página do post, digest semanal e compartilhamento (texto + PDF) via Share Sheet — com testes E2E cobrindo os critérios de aceitação.

**Architecture:** App SwiftUI (projeto gerado por XcodeGen a partir de `project.yml`) que depende do package local `SciNapseKit`. Leitura via `@Query` (SwiftData); escrita/verificação via um `AppServices` injetável (`@MainActor ObservableObject`) que embrulha o `SourceFetcher` + um `MetadataResolving`. Em testes de UI, o resolver real é trocado por um stub determinístico via launch argument — permitindo testar verificação/retração sem rede.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, UIKit (para `UIActivityViewController`/PDF), XCTest/XCUITest. Ferramenta de build: XcodeGen. Plataforma: iOS 17.4.

## Global Constraints

- **Deployment floor:** iOS 17.4.
- **Zero dependências de runtime.** XcodeGen é ferramenta de dev (Homebrew), não vai no app.
- **Regra de publicação:** "ter ≥1 fonte" (não "fonte verificada"). O botão Publicar fica desabilitado com 0 fontes.
- **Retração é inescapável:** fonte retratada mostra banner vermelho em preview, página e digest, independente da camada.
- **Sem segredos no app** (herdado do Kit).
- **TDD:** lógica pura (digest, gate, mapeamento de badge, renderização de texto) testada por unidade; fluxos críticos por XCUITest.
- **UI test hook:** com launch arg `-UITestStubVerification`, o app injeta `UITestResolver` (determinístico, sem rede).

## File Structure

```
SciNapse/
  project.yml                              (XcodeGen)
  Sources/
    App/ScinapseApp.swift                  (@main, ModelContainer, AppServices)
    App/AppServices.swift                  (escrita/verificação; injeta SourceFetcher + resolver)
    App/UITestResolver.swift               (stub determinístico p/ XCUITest)
    Features/Topics/TopicListView.swift
    Features/Topics/TopicDetailView.swift
    Features/Sources/SourceBadge.swift
    Features/Sources/AddSourceSheet.swift
    Features/Sources/SourcePreviewView.swift
    Features/Posts/PostComposer.swift      (lógica pura do gate)
    Features/Posts/ComposePostView.swift
    Features/Posts/PostDetailView.swift
    Features/Digest/DigestModel.swift       (DigestItem/DigestModel + DigestBuilder + DigestTextRenderer)
    Features/Digest/WeeklyDigestView.swift
    Sharing/ShareSheet.swift                (UIActivityViewController bridge)
    Sharing/PDFExporter.swift               (SwiftUI view -> PDF Data)
  Tests/                                   (SciNapseTests — unit)
  UITests/                                 (SciNapseUITests — XCUITest)
```

---

### Task 1: App project (XcodeGen) + entry + AppServices + smoke build

**Files:**
- Create: `SciNapse/project.yml`
- Create: `SciNapse/Sources/App/ScinapseApp.swift`
- Create: `SciNapse/Sources/App/AppServices.swift`
- Create: `SciNapse/Sources/App/UITestResolver.swift`
- Create: `SciNapse/Sources/App/ContentView.swift`
- Test: `SciNapse/Tests/SmokeTests.swift`

**Interfaces:**
- Produces: `@MainActor final class AppServices: ObservableObject` com `init(container: ModelContainer, resolver: any MetadataResolving)`, `func addSource(rawInput: String, topicID: PersistentIdentifier?, postID: PersistentIdentifier?, savedStandalone: Bool) async -> PersistentIdentifier`, `func reverify(_ id: PersistentIdentifier) async`. `struct UITestResolver: MetadataResolving`.

- [ ] **Step 1: Create `project.yml`**

```yaml
# SciNapse/project.yml
name: SciNapse
options:
  bundleIdPrefix: app.scinapse
  deploymentTarget:
    iOS: "17.4"
packages:
  SciNapseKit:
    path: ../SciNapseKit
targets:
  SciNapse:
    type: application
    platform: iOS
    sources: [Sources]
    dependencies:
      - package: SciNapseKit
    info:
      path: Sources/App/Info.plist
      properties:
        UILaunchScreen: {}
        CFBundleDisplayName: SciNapse
    settings:
      base:
        SWIFT_VERSION: "6.0"
        GENERATE_INFOPLIST_FILE: YES
        TARGETED_DEVICE_FAMILY: "1"
  SciNapseTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests]
    dependencies:
      - target: SciNapse
      - package: SciNapseKit
  SciNapseUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies:
      - target: SciNapse
schemes:
  SciNapse:
    build:
      targets:
        SciNapse: all
        SciNapseTests: [test]
        SciNapseUITests: [test]
    test:
      targets: [SciNapseTests, SciNapseUITests]
```

> Remova a chave `info.path` se preferir `GENERATE_INFOPLIST_FILE` puro; mantida aqui só para `CFBundleDisplayName`. Se der conflito, delete o bloco `info:` e deixe o Xcode gerar.

- [ ] **Step 2: Write the failing test**

```swift
// SciNapse/Tests/SmokeTests.swift
import XCTest
import SwiftData
import SciNapseKit
@testable import SciNapse

@MainActor
final class SmokeTests: XCTestCase {
    func test_appServices_addSource_viaStubResolver() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let services = AppServices(container: container, resolver: UITestResolver())
        let id = await services.addSource(rawInput: "10.1/x", topicID: nil, postID: nil, savedStandalone: true)
        let ctx = ModelContext(container)
        let source = ctx.model(for: id) as? Source
        XCTAssertEqual(source?.trustTier, .verified)
    }
}
```

- [ ] **Step 3: Implement entry + services + stub + ContentView**

```swift
// SciNapse/Sources/App/AppServices.swift
import Foundation
import SwiftData
import SciNapseKit

@MainActor
final class AppServices: ObservableObject {
    let container: ModelContainer
    let resolver: any MetadataResolving

    init(container: ModelContainer, resolver: any MetadataResolving) {
        self.container = container
        self.resolver = resolver
    }

    func addSource(rawInput: String, topicID: PersistentIdentifier?, postID: PersistentIdentifier?, savedStandalone: Bool) async -> PersistentIdentifier {
        let fetcher = SourceFetcher(modelContainer: container)
        return await fetcher.addSource(rawInput: rawInput, topicID: topicID, postID: postID, savedStandalone: savedStandalone, using: resolver)
    }

    func reverify(_ id: PersistentIdentifier) async {
        let fetcher = SourceFetcher(modelContainer: container)
        await fetcher.reverify(sourceID: id, using: resolver)
    }
}
```

```swift
// SciNapse/Sources/App/UITestResolver.swift
import Foundation
import SciNapseKit

/// Resolver determinístico p/ XCUITest (sem rede). Decide o resultado pelo conteúdo do input.
struct UITestResolver: MetadataResolving {
    func verify(_ raw: String) async throws -> VerificationResult {
        let lower = raw.lowercased()
        if lower.contains("offline") { throw AppError.offline }
        if lower.contains("retract") || raw.contains("1758835920922055") {
            let m = ResolvedMetadata(title: "Artigo Retratado", authors: ["Doe J"], journal: "J Test", year: 2020, doi: "10.1177/1758835920922055")
            return VerificationResult(metadata: m, trustTier: .verified,
                                      retraction: RetractionInfo(status: .retracted, date: nil, noticeDOI: "10.1/notice"),
                                      resolvedURL: "https://doi.org/\(m.doi!)")
        }
        if lower.contains("who.int") {
            return VerificationResult(metadata: ResolvedMetadata(title: "Página OMS"), trustTier: .recognized, resolvedURL: raw)
        }
        if lower.contains("blog") || lower.contains("example.com") {
            return VerificationResult(metadata: ResolvedMetadata(title: "Blog"), trustTier: .unverified, resolvedURL: raw)
        }
        let m = ResolvedMetadata(title: "Artigo Verificado", authors: ["Silva A", "Souza B"], journal: "N Engl J Med", year: 2022, volume: "1", issue: "2", pages: "10-15", doi: "10.1/x")
        return VerificationResult(metadata: m, trustTier: .verified, resolvedURL: "https://doi.org/10.1/x")
    }
}
```

```swift
// SciNapse/Sources/App/ScinapseApp.swift
import SwiftUI
import SwiftData
import SciNapseKit

@main
struct ScinapseApp: App {
    let container: ModelContainer
    @StateObject private var services: AppServices

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITestInMemory")
        let c = try! ModelContainerFactory.make(inMemory: inMemory)
        self.container = c
        let useStub = ProcessInfo.processInfo.arguments.contains("-UITestStubVerification")
        let resolver: any MetadataResolving = useStub ? UITestResolver() : MetadataService()
        _services = StateObject(wrappedValue: AppServices(container: c, resolver: resolver))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(services)
        }
        .modelContainer(container)
    }
}
```

```swift
// SciNapse/Sources/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TopicListView()
    }
}
```

- [ ] **Step 4: Generate project + run the smoke test**

Run:
```bash
cd SciNapse
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate
xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseTests/SmokeTests 2>&1 | tail -20
```
Expected: build OK; `SmokeTests` PASS. (Se `iPhone 16` não existir, rode `xcrun simctl list devices available` e troque o nome.)

> Crie um `TopicListView` mínimo temporário se o build reclamar — ele é implementado de verdade na Task 2. Para destravar este smoke, um stub `struct TopicListView: View { var body: some View { Text("ok") } }` em `Features/Topics/TopicListView.swift` é aceitável e será substituído.

- [ ] **Step 5: Commit**

```bash
git add SciNapse && git commit -m "feat(app): XcodeGen project + AppServices + UITestResolver smoke"
```

---

### Task 2: Topics (lista + detalhe)

**Files:**
- Create/replace: `SciNapse/Sources/Features/Topics/TopicListView.swift`
- Create: `SciNapse/Sources/Features/Topics/TopicDetailView.swift`
- Test: `SciNapse/UITests/TopicsUITests.swift`

**Interfaces:**
- Consumes: `Topic`, `Post`, `Source` (SciNapseKit), `AppServices`.
- Produces: `struct TopicListView: View`, `struct TopicDetailView: View` (init `init(topic: Topic)`).

- [ ] **Step 1: Write the failing UI test (AC1 — persistência/criação)**

```swift
// SciNapse/UITests/TopicsUITests.swift
import XCTest

final class TopicsUITests: XCTestCase {
    func test_createTopic_appearsInList() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStubVerification", "-UITestInMemory"]
        app.launch()

        app.buttons["addTopicButton"].tap()
        let field = app.textFields["topicNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Cardiologia")
        app.buttons["saveTopicButton"].tap()

        XCTAssertTrue(app.staticTexts["Cardiologia"].waitForExistence(timeout: 2))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapse && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseUITests/TopicsUITests 2>&1 | tail -20`
Expected: FAIL — botão `addTopicButton` não existe.

- [ ] **Step 3: Implement TopicListView**

```swift
// SciNapse/Sources/Features/Topics/TopicListView.swift
import SwiftUI
import SwiftData
import SciNapseKit

struct TopicListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.createdAt, order: .reverse) private var topics: [Topic]
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(topics) { topic in
                    NavigationLink(value: topic.id) {
                        VStack(alignment: .leading) {
                            Text(topic.title).font(.headline)
                            Text("\(topic.posts.count) posts").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationDestination(for: UUID.self) { id in
                if let topic = topics.first(where: { $0.id == id }) {
                    TopicDetailView(topic: topic)
                }
            }
            .navigationTitle("SciNapse")
            .overlay { if topics.isEmpty { ContentUnavailableView("Nenhum tópico", systemImage: "tray", description: Text("Crie um tópico para começar")) } }
            .toolbar {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("addTopicButton")
            }
            .alert("Novo tópico", isPresented: $showingNew) {
                TextField("Nome", text: $newName).accessibilityIdentifier("topicNameField")
                Button("Salvar") { addTopic() }.accessibilityIdentifier("saveTopicButton")
                Button("Cancelar", role: .cancel) { newName = "" }
            }
        }
    }

    private func addTopic() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.insert(Topic(title: trimmed))
        try? context.save()
        newName = ""
    }
    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(topics[i]) }
        try? context.save()
    }
}
```

- [ ] **Step 4: Implement TopicDetailView**

```swift
// SciNapse/Sources/Features/Topics/TopicDetailView.swift
import SwiftUI
import SwiftData
import SciNapseKit

struct TopicDetailView: View {
    @Bindable var topic: Topic
    @State private var showingAddSource = false
    @State private var showingCompose = false
    @State private var showingDigest = false

    private var publishedPosts: [Post] { topic.posts.filter { $0.status == .published }.sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) } }
    private var savedSources: [Source] { (try? topic.modelContext?.fetch(FetchDescriptor<Source>())) ?? [] }

    var body: some View {
        List {
            Section("Posts") {
                if publishedPosts.isEmpty { Text("Sem posts ainda").foregroundStyle(.secondary) }
                ForEach(publishedPosts) { post in
                    NavigationLink { PostDetailView(post: post) } label: {
                        VStack(alignment: .leading) {
                            Text(post.title).font(.headline)
                            Text("\(post.sources.count) fontes").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(topic.title)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { showingCompose = true } label: { Label("Novo post", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("newPostButton")
                Spacer()
                Button { showingAddSource = true } label: { Label("Salvar artigo", systemImage: "bookmark") }
                    .accessibilityIdentifier("saveArticleButton")
                Spacer()
                Button { showingDigest = true } label: { Label("Digest", systemImage: "newspaper") }
                    .accessibilityIdentifier("digestButton")
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddSourceSheet(topic: topic, post: nil)
        }
        .sheet(isPresented: $showingCompose) {
            ComposePostView(topic: topic)
        }
        .sheet(isPresented: $showingDigest) {
            WeeklyDigestView(topic: topic)
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd SciNapse && xcodegen generate && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseUITests/TopicsUITests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add SciNapse && git commit -m "feat(app): topic list + detail screens"
```

---

### Task 3: SourceBadge + AddSourceSheet + SourcePreviewView

**Files:**
- Create: `SciNapse/Sources/Features/Sources/SourceBadge.swift`
- Create: `SciNapse/Sources/Features/Sources/SourcePreviewView.swift`
- Create: `SciNapse/Sources/Features/Sources/AddSourceSheet.swift`
- Test: `SciNapse/Tests/SourceBadgeTests.swift`
- Test: `SciNapse/UITests/AddSourceUITests.swift`

**Interfaces:**
- Consumes: `Source`, `TrustTier`, `RetractionStatus`, `AppServices`.
- Produces: `struct SourceBadge: View` (init `init(tier: TrustTier, retraction: RetractionStatus)`), `enum BadgeStyle { static func label(_ tier: TrustTier) -> String; static func symbol(_ tier: TrustTier) -> String }`, `struct SourcePreviewView: View` (init `init(source: Source)`), `struct AddSourceSheet: View` (init `init(topic: Topic, post: Post?)`).

- [ ] **Step 1: Write the failing unit test (badge mapping)**

```swift
// SciNapse/Tests/SourceBadgeTests.swift
import XCTest
import SciNapseKit
@testable import SciNapse

final class SourceBadgeTests: XCTestCase {
    func test_labels() {
        XCTAssertEqual(BadgeStyle.label(.verified), "Verificada")
        XCTAssertEqual(BadgeStyle.label(.recognized), "Reconhecida")
        XCTAssertEqual(BadgeStyle.label(.unverified), "Não verificada")
    }
    func test_symbols_areDistinct() {
        let set = Set([BadgeStyle.symbol(.verified), BadgeStyle.symbol(.recognized), BadgeStyle.symbol(.unverified)])
        XCTAssertEqual(set.count, 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapse && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseTests/SourceBadgeTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'BadgeStyle'".

- [ ] **Step 3: Implement SourceBadge**

```swift
// SciNapse/Sources/Features/Sources/SourceBadge.swift
import SwiftUI
import SciNapseKit

enum BadgeStyle {
    static func label(_ tier: TrustTier) -> String {
        switch tier {
        case .verified: return "Verificada"
        case .recognized: return "Reconhecida"
        case .unverified: return "Não verificada"
        }
    }
    static func symbol(_ tier: TrustTier) -> String {
        switch tier {
        case .verified: return "checkmark.seal.fill"
        case .recognized: return "checkmark.shield"
        case .unverified: return "exclamationmark.triangle"
        }
    }
    static func color(_ tier: TrustTier) -> Color {
        switch tier {
        case .verified: return .green
        case .recognized: return .blue
        case .unverified: return .orange
        }
    }
}

struct SourceBadge: View {
    let tier: TrustTier
    let retraction: RetractionStatus

    var body: some View {
        HStack(spacing: 6) {
            Label(BadgeStyle.label(tier), systemImage: BadgeStyle.symbol(tier))
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                .background(BadgeStyle.color(tier).opacity(0.15), in: Capsule())
                .foregroundStyle(BadgeStyle.color(tier))
            if retraction != .none {
                Label(retractionText, systemImage: "xmark.octagon.fill")
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red.opacity(0.15), in: Capsule())
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("retractionBadge")
            }
        }
    }
    private var retractionText: String {
        switch retraction {
        case .retracted: return "Retratado"
        case .concern: return "Com ressalva"
        case .correction: return "Corrigido"
        case .none: return ""
        }
    }
}
```

- [ ] **Step 4: Implement SourcePreviewView + AddSourceSheet**

```swift
// SciNapse/Sources/Features/Sources/SourcePreviewView.swift
import SwiftUI
import SciNapseKit

struct SourcePreviewView: View {
    let source: Source
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if source.retractionStatus != .none {
                Text("⚠️ Artigo retratado\(source.retractionDate.map { " em \(yearOf($0))" } ?? "")")
                    .font(.subheadline.bold()).foregroundStyle(.red)
            }
            Text(source.title ?? source.rawInput).font(.headline)
            if !source.authors.isEmpty {
                Text(source.authors.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
            }
            if let j = source.journal {
                Text("\(j)\(source.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
            }
            SourceBadge(tier: source.trustTier, retraction: source.retractionStatus)
            if source.isOpenAccess, let oa = source.oaURL, let url = URL(string: oa) {
                Link("Acesso aberto", destination: url).font(.caption)
            }
            if let cit = source.formattedCitation {
                Text(cit).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    private func yearOf(_ d: Date) -> Int { Calendar.current.component(.year, from: d) }
}
```

```swift
// SciNapse/Sources/Features/Sources/AddSourceSheet.swift
import SwiftUI
import SwiftData
import SciNapseKit

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    let topic: Topic
    let post: Post?

    @State private var input = ""
    @State private var state: ViewState = .editing
    @State private var previewSource: Source?

    enum ViewState: Equatable { case editing, verifying, done }

    var body: some View {
        NavigationStack {
            Form {
                Section("DOI, PMID ou link") {
                    TextField("ex: 10.1056/… ou https://…", text: $input, axis: .vertical)
                        .accessibilityIdentifier("sourceInputField")
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if state == .verifying { HStack { ProgressView(); Text("Verificando…") } }
                if let s = previewSource { Section("Pré-visualização") { SourcePreviewView(source: s) } }
            }
            .navigationTitle(post == nil ? "Salvar artigo" : "Adicionar fonte")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(state == .done ? "Concluir" : "Verificar") { Task { await primaryAction() } }
                        .accessibilityIdentifier("verifySourceButton")
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || state == .verifying)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
    }

    private func primaryAction() async {
        if state == .done { dismiss(); return }
        state = .verifying
        let id = await services.addSource(rawInput: input, topicID: topic.persistentModelID,
                                          postID: post?.persistentModelID, savedStandalone: post == nil)
        let ctx = ModelContext(services.container)
        previewSource = ctx.model(for: id) as? Source
        state = .done
    }
}
```

- [ ] **Step 5: Write the failing UI test (AC2/AC3/AC5 — verificação + retração)**

```swift
// SciNapse/UITests/AddSourceUITests.swift
import XCTest

final class AddSourceUITests: XCTestCase {
    private func launchToTopic() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStubVerification", "-UITestInMemory"]
        app.launch()
        app.buttons["addTopicButton"].tap()
        app.textFields["topicNameField"].typeText("Tópico")
        app.buttons["saveTopicButton"].tap()
        app.staticTexts["Tópico"].tap()
        return app
    }

    func test_verifiedSource_showsVerifiedBadge() {
        let app = launchToTopic()
        app.buttons["saveArticleButton"].tap()
        app.textViews["sourceInputField"].tap()
        app.textViews["sourceInputField"].typeText("10.1/x")
        app.buttons["verifySourceButton"].tap()
        XCTAssertTrue(app.staticTexts["Verificada"].waitForExistence(timeout: 3))
    }

    func test_retractedSource_showsRetractionBadge() {
        let app = launchToTopic()
        app.buttons["saveArticleButton"].tap()
        app.textViews["sourceInputField"].tap()
        app.textViews["sourceInputField"].typeText("10.1177/1758835920922055")
        app.buttons["verifySourceButton"].tap()
        XCTAssertTrue(app.staticTexts["Retratado"].waitForExistence(timeout: 3))
    }

    func test_blogSource_showsUnverified() {
        let app = launchToTopic()
        app.buttons["saveArticleButton"].tap()
        app.textViews["sourceInputField"].tap()
        app.textViews["sourceInputField"].typeText("https://blog.example.com/post")
        app.buttons["verifySourceButton"].tap()
        XCTAssertTrue(app.staticTexts["Não verificada"].waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:
```bash
cd SciNapse && xcodegen generate
xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SciNapseTests/SourceBadgeTests -only-testing:SciNapseUITests/AddSourceUITests 2>&1 | tail -25
```
Expected: PASS (2 unit + 3 UI).

- [ ] **Step 7: Commit**

```bash
git add SciNapse && git commit -m "feat(app): add-source sheet with trust badges + retraction alert"
```

---

### Task 4: ComposePostView + publish gate

**Files:**
- Create: `SciNapse/Sources/Features/Posts/PostComposer.swift`
- Create: `SciNapse/Sources/Features/Posts/ComposePostView.swift`
- Test: `SciNapse/Tests/PostComposerTests.swift`
- Test: `SciNapse/UITests/PublishGateUITests.swift`

**Interfaces:**
- Consumes: `Topic`, `Post`, `Source`, `PostStatus`, `AppServices`.
- Produces: `enum PostComposer { static func canPublish(title: String, sourceCount: Int) -> Bool }`, `struct ComposePostView: View` (init `init(topic: Topic)`).

- [ ] **Step 1: Write the failing unit test (gate logic — AC6)**

```swift
// SciNapse/Tests/PostComposerTests.swift
import XCTest
@testable import SciNapse

final class PostComposerTests: XCTestCase {
    func test_cannotPublish_withZeroSources() {
        XCTAssertFalse(PostComposer.canPublish(title: "T", sourceCount: 0))
    }
    func test_cannotPublish_withEmptyTitle() {
        XCTAssertFalse(PostComposer.canPublish(title: "   ", sourceCount: 2))
    }
    func test_canPublish_withTitleAndOneSource() {
        XCTAssertTrue(PostComposer.canPublish(title: "T", sourceCount: 1))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapse && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseTests/PostComposerTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'PostComposer'".

- [ ] **Step 3: Implement PostComposer + ComposePostView**

```swift
// SciNapse/Sources/Features/Posts/PostComposer.swift
import Foundation

enum PostComposer {
    static func canPublish(title: String, sourceCount: Int) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sourceCount >= 1
    }
}
```

```swift
// SciNapse/Sources/Features/Posts/ComposePostView.swift
import SwiftUI
import SwiftData
import SciNapseKit

struct ComposePostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let topic: Topic

    @State private var title = ""
    @State private var body_ = ""
    @State private var draft: Post?
    @State private var showingAddSource = false

    private var sources: [Source] { draft?.sources ?? [] }
    private var canPublish: Bool { PostComposer.canPublish(title: title, sourceCount: sources.count) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Título") {
                    TextField("Título do achado", text: $title).accessibilityIdentifier("postTitleField")
                }
                Section("Síntese") {
                    TextField("O que você descobriu…", text: $body_, axis: .vertical)
                        .lineLimit(4...10).accessibilityIdentifier("postBodyField")
                }
                Section("Fontes (mín. 1 para publicar)") {
                    ForEach(sources) { s in
                        HStack {
                            Text(s.title ?? s.rawInput).lineLimit(1)
                            Spacer()
                            SourceBadge(tier: s.trustTier, retraction: s.retractionStatus)
                        }
                    }
                    Button { ensureDraft(); showingAddSource = true } label: { Label("Adicionar fonte", systemImage: "plus") }
                        .accessibilityIdentifier("addSourceToPostButton")
                }
            }
            .navigationTitle("Novo post")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publicar") { publish() }
                        .accessibilityIdentifier("publishButton")
                        .disabled(!canPublish)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cancel() } }
            }
            .sheet(isPresented: $showingAddSource, onDismiss: {}) {
                if let draft { AddSourceSheet(topic: topic, post: draft) }
            }
        }
    }

    private func ensureDraft() {
        if draft == nil {
            let p = Post(title: title, body: body_, status: .draft)
            p.topic = topic
            context.insert(p)
            try? context.save()
            draft = p
        }
    }
    private func publish() {
        ensureDraft()
        guard let draft else { return }
        draft.title = title
        draft.body = body_
        draft.status = .published
        draft.publishedAt = Date()
        draft.updatedAt = Date()
        try? context.save()
        dismiss()
    }
    private func cancel() {
        if let draft, draft.status == .draft { context.delete(draft); try? context.save() }
        dismiss()
    }
}
```

- [ ] **Step 4: Write the failing UI test (publish disabled until a source exists)**

```swift
// SciNapse/UITests/PublishGateUITests.swift
import XCTest

final class PublishGateUITests: XCTestCase {
    func test_publishDisabled_untilSourceAdded() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStubVerification", "-UITestInMemory"]
        app.launch()
        app.buttons["addTopicButton"].tap()
        app.textFields["topicNameField"].typeText("T")
        app.buttons["saveTopicButton"].tap()
        app.staticTexts["T"].tap()

        app.buttons["newPostButton"].tap()
        app.textFields["postTitleField"].tap()
        app.textFields["postTitleField"].typeText("Meu achado")
        XCTAssertFalse(app.buttons["publishButton"].isEnabled, "sem fonte, Publicar fica desabilitado")

        app.buttons["addSourceToPostButton"].tap()
        app.textViews["sourceInputField"].tap()
        app.textViews["sourceInputField"].typeText("10.1/x")
        app.buttons["verifySourceButton"].tap()
        app.buttons["verifySourceButton"].tap() // "Concluir" fecha a sheet
        XCTAssertTrue(app.buttons["publishButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["publishButton"].isEnabled, "com 1 fonte, Publicar habilita")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
cd SciNapse && xcodegen generate
xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SciNapseTests/PostComposerTests -only-testing:SciNapseUITests/PublishGateUITests 2>&1 | tail -25
```
Expected: PASS (3 unit + 1 UI).

- [ ] **Step 6: Commit**

```bash
git add SciNapse && git commit -m "feat(app): compose post with publish gate (>=1 source)"
```

---

### Task 5: PostDetailView (a "página")

**Files:**
- Create: `SciNapse/Sources/Features/Posts/PostDetailView.swift`
- Test: `SciNapse/UITests/PostPageUITests.swift`

**Interfaces:**
- Consumes: `Post`, `Source`, `AppServices`.
- Produces: `struct PostDetailView: View` (init `init(post: Post)`).

- [ ] **Step 1: Write the failing UI test (AC7 — página com síntese + fontes)**

```swift
// SciNapse/UITests/PostPageUITests.swift
import XCTest

final class PostPageUITests: XCTestCase {
    func test_publishedPost_pageShowsSourcesAndShare() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStubVerification", "-UITestInMemory"]
        app.launch()
        app.buttons["addTopicButton"].tap()
        app.textFields["topicNameField"].typeText("T")
        app.buttons["saveTopicButton"].tap()
        app.staticTexts["T"].tap()
        // criar e publicar post com 1 fonte
        app.buttons["newPostButton"].tap()
        app.textFields["postTitleField"].tap(); app.textFields["postTitleField"].typeText("Achado X")
        app.buttons["addSourceToPostButton"].tap()
        app.textViews["sourceInputField"].tap(); app.textViews["sourceInputField"].typeText("10.1/x")
        app.buttons["verifySourceButton"].tap(); app.buttons["verifySourceButton"].tap()
        app.buttons["publishButton"].tap()
        // abrir a página
        app.staticTexts["Achado X"].tap()
        XCTAssertTrue(app.staticTexts["Fontes"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["sharePostButton"].exists)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapse && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseUITests/PostPageUITests 2>&1 | tail -20`
Expected: FAIL — `Fontes` não aparece.

- [ ] **Step 3: Implement PostDetailView**

```swift
// SciNapse/Sources/Features/Posts/PostDetailView.swift
import SwiftUI
import SciNapseKit

struct PostDetailView: View {
    let post: Post
    @State private var shareItems: [Any]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(post.title).font(.largeTitle.bold())
                if let t = post.topic { Text(t.title).font(.subheadline).foregroundStyle(.secondary) }
                Text(post.body).font(.body)
                Divider()
                Text("Fontes").font(.title2.bold())
                ForEach(post.sources) { s in
                    SourcePreviewView(source: s).padding(.vertical, 4)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { shareItems = PostShare.items(for: post) } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityIdentifier("sharePostButton")
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ShareSheet(activityItems: items) }
        }
    }
}

enum PostShare {
    static func text(for post: Post) -> String {
        var lines = ["# \(post.title)", "", post.body, "", "## Fontes"]
        for s in post.sources {
            let cit = s.formattedCitation ?? (s.title ?? s.rawInput)
            let flag = s.retractionStatus == .none ? "" : " [RETRATADO]"
            lines.append("- \(cit)\(flag)")
        }
        return lines.joined(separator: "\n")
    }
    static func items(for post: Post) -> [Any] { [text(for: post)] }
}
```

> `ShareSheet` é criado na Task 7. Para destravar esta task, adicione um stub temporário `struct ShareSheet: UIViewControllerRepresentable { let activityItems: [Any]; func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: activityItems, applicationActivities: nil) }; func updateUIViewController(_ vc: UIActivityViewController, context: Context) {} }` em `Sharing/ShareSheet.swift` — a Task 7 o completa (anchor de iPad).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapse && xcodegen generate && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseUITests/PostPageUITests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SciNapse && git commit -m "feat(app): post detail page with sources + share entry point"
```

---

### Task 6: Digest (builder + view)

**Files:**
- Create: `SciNapse/Sources/Features/Digest/DigestModel.swift`
- Create: `SciNapse/Sources/Features/Digest/WeeklyDigestView.swift`
- Test: `SciNapse/Tests/DigestBuilderTests.swift`

**Interfaces:**
- Consumes: `Post`, `Source`, `ModelContainerFactory` (para teste).
- Produces: `struct DigestItem`, `struct DigestModel`, `enum DigestBuilder { static func build(topicTitle: String, posts: [Post], now: Date, days: Int) -> DigestModel }`, `enum DigestTextRenderer { static func markdown(_ model: DigestModel) -> String }`, `struct WeeklyDigestView: View` (init `init(topic: Topic)`).

- [ ] **Step 1: Write the failing unit test (AC8 — agregação por janela)**

```swift
// SciNapse/Tests/DigestBuilderTests.swift
import XCTest
import SwiftData
import SciNapseKit
@testable import SciNapse

@MainActor
final class DigestBuilderTests: XCTestCase {
    func test_includesOnlyPostsWithinWindow() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let ctx = container.mainContext
        let now = Date()
        let recent = Post(title: "Recente", body: "b", status: .published)
        recent.publishedAt = now.addingTimeInterval(-2 * 86400)
        let old = Post(title: "Velho", body: "b", status: .published)
        old.publishedAt = now.addingTimeInterval(-30 * 86400)
        ctx.insert(recent); ctx.insert(old)
        try ctx.save()

        let model = DigestBuilder.build(topicTitle: "T", posts: [recent, old], now: now, days: 7)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.items.first?.title, "Recente")
    }
    func test_markdown_rendersTitleAndItems() throws {
        let model = DigestModel(topicTitle: "Cardio", from: Date(), to: Date(),
                                items: [DigestItem(title: "A", body: "corpo", citations: ["Cit 1"], publishedAt: Date())])
        let md = DigestTextRenderer.markdown(model)
        XCTAssertTrue(md.contains("Cardio"))
        XCTAssertTrue(md.contains("A"))
        XCTAssertTrue(md.contains("Cit 1"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapse && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseTests/DigestBuilderTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'DigestBuilder'".

- [ ] **Step 3: Implement DigestModel + builder + renderer**

```swift
// SciNapse/Sources/Features/Digest/DigestModel.swift
import Foundation
import SciNapseKit

struct DigestItem: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let citations: [String]
    let publishedAt: Date
}

struct DigestModel {
    let topicTitle: String
    let from: Date
    let to: Date
    let items: [DigestItem]
}

enum DigestBuilder {
    static func build(topicTitle: String, posts: [Post], now: Date, days: Int = 7) -> DigestModel {
        let from = now.addingTimeInterval(-Double(days) * 86400)
        let items = posts
            .filter { $0.status == .published }
            .filter { let d = $0.publishedAt ?? $0.createdAt; return d >= from && d <= now }
            .sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }
            .map { post in
                DigestItem(title: post.title, body: post.body,
                           citations: post.sources.map { $0.formattedCitation ?? ($0.title ?? $0.rawInput) + (($0.retractionStatus != .none) ? " [RETRATADO]" : "") },
                           publishedAt: post.publishedAt ?? post.createdAt)
            }
        return DigestModel(topicTitle: topicTitle, from: from, to: now, items: items)
    }
}

enum DigestTextRenderer {
    static func markdown(_ model: DigestModel) -> String {
        let df = DateFormatter(); df.dateStyle = .medium
        var lines = ["# \(model.topicTitle) — principais publicações da semana",
                     "_\(df.string(from: model.from)) – \(df.string(from: model.to))_", ""]
        if model.items.isEmpty { lines.append("Nenhum post publicado neste período.") }
        for item in model.items {
            lines.append("## \(item.title)")
            lines.append(item.body)
            if !item.citations.isEmpty {
                lines.append("")
                lines.append("**Fontes:**")
                for c in item.citations { lines.append("- \(c)") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Implement WeeklyDigestView**

```swift
// SciNapse/Sources/Features/Digest/WeeklyDigestView.swift
import SwiftUI
import SciNapseKit

struct WeeklyDigestView: View {
    @Environment(\.dismiss) private var dismiss
    let topic: Topic
    @State private var shareItems: [Any]?

    private var model: DigestModel { DigestBuilder.build(topicTitle: topic.title, posts: topic.posts, now: Date(), days: 7) }

    var body: some View {
        NavigationStack {
            ScrollView {
                DigestPageView(model: model).padding()
            }
            .navigationTitle("Digest da semana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { share() } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityIdentifier("shareDigestButton")
                        .disabled(model.items.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
            }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                if let items = shareItems { ShareSheet(activityItems: items) }
            }
        }
    }

    @MainActor private func share() {
        let text = DigestTextRenderer.markdown(model)
        let pdf = PDFExporter.pdf(from: DigestPageView(model: model).frame(width: 540), pageSize: CGSize(width: 595, height: 842))
        var items: [Any] = [text]
        if let url = PDFExporter.writeTempPDF(pdf, name: "digest.pdf") { items.append(url) }
        shareItems = items
    }
}

struct DigestPageView: View {
    let model: DigestModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.topicTitle).font(.title.bold())
            Text("Principais publicações da semana").font(.subheadline).foregroundStyle(.secondary)
            if model.items.isEmpty { Text("Nenhum post publicado neste período.").foregroundStyle(.secondary) }
            ForEach(model.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    Text(item.body).font(.body)
                    ForEach(item.citations, id: \.self) { c in Text("• \(c)").font(.caption).foregroundStyle(.secondary) }
                }
                Divider()
            }
        }
    }
}
```

> `PDFExporter` e `ShareSheet` vêm da Task 7. Se ainda não existirem, adicione os stubs temporários (ver Tasks 5 e 7) para compilar; a Task 7 os finaliza.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd SciNapse && xcodegen generate && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseTests/DigestBuilderTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add SciNapse && git commit -m "feat(app): weekly digest builder + view"
```

---

### Task 7: Sharing (ShareSheet + PDFExporter)

**Files:**
- Create/replace: `SciNapse/Sources/Sharing/ShareSheet.swift`
- Create: `SciNapse/Sources/Sharing/PDFExporter.swift`
- Test: `SciNapse/Tests/PDFExporterTests.swift`

**Interfaces:**
- Produces: `struct ShareSheet: UIViewControllerRepresentable` (init `init(activityItems: [Any])`), `enum PDFExporter` com `@MainActor static func pdf(from view: some View, pageSize: CGSize) -> Data` e `static func writeTempPDF(_ data: Data, name: String) -> URL?`.

- [ ] **Step 1: Write the failing unit test (PDF não vazio + começa com %PDF)**

```swift
// SciNapse/Tests/PDFExporterTests.swift
import XCTest
import SwiftUI
@testable import SciNapse

@MainActor
final class PDFExporterTests: XCTestCase {
    func test_pdf_isNonEmptyAndHasHeader() {
        let data = PDFExporter.pdf(from: Text("Olá").frame(width: 200, height: 100), pageSize: CGSize(width: 300, height: 200))
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
    }
    func test_writeTempPDF_returnsURL() {
        let url = PDFExporter.writeTempPDF(Data("%PDF-1.7".utf8), name: "x.pdf")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.lastPathComponent, "x.pdf")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SciNapse && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseTests/PDFExporterTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'PDFExporter'".

- [ ] **Step 3: Implement ShareSheet + PDFExporter**

```swift
// SciNapse/Sources/Sharing/ShareSheet.swift
import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        // Anchor para iPad (evita crash em popover).
        if let pop = vc.popoverPresentationController {
            pop.sourceView = context.coordinator.anchorView
            pop.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { let anchorView = UIView() }
}
```

```swift
// SciNapse/Sources/Sharing/PDFExporter.swift
import SwiftUI
import UIKit

enum PDFExporter {
    @MainActor
    static func pdf(from view: some View, pageSize: CGSize) -> Data {
        let renderer = ImageRenderer(content:
            view.frame(width: pageSize.width, alignment: .topLeading)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2.0
        var data = Data()
        renderer.render { size, renderInContext in
            var box = CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: max(size.height, pageSize.height)))
            let mutableData = CFDataCreateMutable(nil, 0)!
            guard let consumer = CGDataConsumer(data: mutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            data = mutableData as Data
        }
        return data
    }

    static func writeTempPDF(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch { return nil }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SciNapse && xcodegen generate && xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SciNapseTests/PDFExporterTests 2>&1 | tail -20`
Expected: PASS (2 tests). Remova quaisquer stubs temporários de `ShareSheet` criados nas Tasks 5/6.

- [ ] **Step 5: Commit**

```bash
git add SciNapse && git commit -m "feat(app): ShareSheet bridge + SwiftUI->PDF exporter"
```

---

### Task 8: E2E — digest share + offline + suíte completa

**Files:**
- Create: `SciNapse/UITests/DigestShareUITests.swift`
- Create: `SciNapse/UITests/OfflineUITests.swift`
- Create: `SciNapse/MANUAL_TEST.md` (roteiro p/ ACs que exigem rede real)

**Interfaces:**
- Consumes: tudo das tasks anteriores.

- [ ] **Step 1: Write the digest-share UI test (AC8) + offline test (AC9)**

```swift
// SciNapse/UITests/DigestShareUITests.swift
import XCTest

final class DigestShareUITests: XCTestCase {
    func test_digestShare_opensShareSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStubVerification", "-UITestInMemory"]
        app.launch()
        app.buttons["addTopicButton"].tap()
        app.textFields["topicNameField"].typeText("T")
        app.buttons["saveTopicButton"].tap()
        app.staticTexts["T"].tap()
        // publica 1 post
        app.buttons["newPostButton"].tap()
        app.textFields["postTitleField"].tap(); app.textFields["postTitleField"].typeText("Achado")
        app.buttons["addSourceToPostButton"].tap()
        app.textViews["sourceInputField"].tap(); app.textViews["sourceInputField"].typeText("10.1/x")
        app.buttons["verifySourceButton"].tap(); app.buttons["verifySourceButton"].tap()
        app.buttons["publishButton"].tap()
        // abre digest e compartilha
        app.buttons["digestButton"].tap()
        XCTAssertTrue(app.buttons["shareDigestButton"].waitForExistence(timeout: 2))
        app.buttons["shareDigestButton"].tap()
        // a share sheet do sistema aparece (verifica algum elemento de activity)
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 4) || app.collectionViews.firstMatch.waitForExistence(timeout: 4))
    }
}
```

```swift
// SciNapse/UITests/OfflineUITests.swift
import XCTest

final class OfflineUITests: XCTestCase {
    func test_offlineSource_isPendingThenSavable() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStubVerification", "-UITestInMemory"]
        app.launch()
        app.buttons["addTopicButton"].tap()
        app.textFields["topicNameField"].typeText("T")
        app.buttons["saveTopicButton"].tap()
        app.staticTexts["T"].tap()
        app.buttons["saveArticleButton"].tap()
        app.textViews["sourceInputField"].tap()
        app.textViews["sourceInputField"].typeText("offline-doi") // UITestResolver lança .offline
        app.buttons["verifySourceButton"].tap()
        // Pendente => badge "Não verificada" aparece (trustTier=.unverified, state=.pending)
        XCTAssertTrue(app.staticTexts["Não verificada"].waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 2: Run the new UI tests**

Run:
```bash
cd SciNapse && xcodegen generate
xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SciNapseUITests/DigestShareUITests -only-testing:SciNapseUITests/OfflineUITests 2>&1 | tail -25
```
Expected: PASS. (Se a asserção da share sheet do sistema for instável no seu runner, troque por verificar que `app.buttons["shareDigestButton"]` permanece e a sheet abriu — ajuste o seletor conforme `xcrun simctl`/versão do iOS.)

- [ ] **Step 3: Write the manual test script for network-dependent ACs**

```markdown
<!-- SciNapse/MANUAL_TEST.md -->
# Roteiro manual — ACs que exigem rede real (sem stub)

Pré: rodar o app SEM `-UITestStubVerification` num device/simulador com internet.

- AC2 (DOI verificado): Salvar artigo → colar `10.1056/NEJMoa2034577` → deve resolver título/autores/journal e badge **Verificada**.
- AC3 (retração): colar `10.1177/1758835920922055` → banner vermelho **Retratado**.
- AC4 (reconhecida): colar `https://www.who.int/news-room/fact-sheets/detail/hypertension` → badge **Reconhecida**.
- AC5 (não verificada): colar um link de blog qualquer → **Não verificada**.
- AC10 (PMID): colar `33535474` → resolve via PubMed → **Verificada**.
- AC1 (persistência): criar tópico/post, fechar e reabrir o app (sem `-UITestInMemory`) → dados persistem.
```

- [ ] **Step 4: Run the FULL test suite**

Run:
```bash
cd SciNapse && xcodegen generate
xcodebuild test -scheme SciNapse -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```
Expected: PASS — SmokeTests, SourceBadgeTests, PostComposerTests, DigestBuilderTests, PDFExporterTests, TopicsUITests, AddSourceUITests, PublishGateUITests, PostPageUITests, DigestShareUITests, OfflineUITests.

- [ ] **Step 5: Commit**

```bash
git add SciNapse && git commit -m "test(app): E2E digest-share + offline + manual AC script"
```

---

## Self-Review (preenchido)

**Spec coverage (mapeado para ACs):** AC1→Task 2 (criação/lista; persistência via relaunch no roteiro manual); AC2/AC3/AC5→Task 3 (stub) + roteiro manual (rede real); AC4→roteiro manual; AC6→Task 4 (gate, unit + UI); AC7→Task 5 (página); AC8→Tasks 6+7+8 (digest + PDF + share); AC9→Task 8 (offline pendente); AC10→roteiro manual. Telas §9 → Tasks 2–6; digest §8 → Task 6; sharing §8 → Task 7.

**Placeholder scan:** sem TODO/“tratar erros”/“similar a”. Steps com stub temporário (ShareSheet/TopicListView/PDFExporter) explicitam o código do stub e qual task o substitui — não é placeholder, é sequência de build declarada.

**Type consistency:** `AppServices.addSource/reverify` idênticos entre Tasks 1–4; `SourceBadge(tier:retraction:)` usado igual nas Tasks 3,4,5; `DigestBuilder.build(topicTitle:posts:now:days:)` e `DigestTextRenderer.markdown(_:)` consistentes Tasks 6,8; `PDFExporter.pdf(from:pageSize:)`/`writeTempPDF(_:name:)` e `ShareSheet(activityItems:)` consistentes Tasks 5,6,7.

> **Nota de cobertura (sem cap silencioso):** as ACs que dependem de rede real (AC2/AC3/AC4/AC5/AC10 com APIs públicas, AC1 com persistência em disco) são verificadas pelo `MANUAL_TEST.md`, não por XCUITest — testes de UI usam o `UITestResolver` determinístico (sem rede) e `-UITestInMemory`. Isso é intencional: mantém a suíte automatizada rápida e estável; a validação contra as APIs reais é um passo manual explícito antes de declarar a fase concluída.
