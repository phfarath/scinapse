import SwiftUI
import SwiftData
import SciNapseKit

struct TopicDetailView: View {
    @Bindable var topic: Topic
    @Environment(\.modelContext) private var context
    @State private var showingAddSource = false
    @State private var showingCompose = false
    @State private var showingDigest = false
    @State private var isPublishing = false
    @State private var publishError: String?
    @State private var showShare = false
    @State private var views: Int?
    @State private var showConfirmUnpublish = false

    @Query private var allSaved: [Source]

    init(topic: Topic) {
        self.topic = topic
        _allSaved = Query(filter: #Predicate<Source> { $0.savedStandalone }, sort: \Source.createdAt, order: .reverse)
    }

    private var publishedPosts: [Post] {
        topic.posts.filter { $0.status == .published }
            .sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }
    }
    private var savedArticles: [Source] { allSaved.filter { $0.topic?.id == topic.id } }
    private var publishedURL: URL? { topic.remoteID.flatMap { PublishClient.publicURL(forSlug: $0) } }

    var body: some View {
        List {
            Section {
                if let url = publishedURL {
                    HStack {
                        Label("Publicado", systemImage: "checkmark.seal.fill").foregroundStyle(Brand.tealDeep)
                        Spacer()
                        if let v = views {
                            Label("\(v)", systemImage: "eye").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: url) {
                        Text(url.absoluteString).font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                    Button { showShare = true } label: { Label("Compartilhar link", systemImage: "square.and.arrow.up") }
                    Menu {
                        Button { publishPage(scope: .all) } label: { Label("Tudo", systemImage: "tray.full") }
                        Button { publishPage(scope: .lastWeek) } label: { Label("Última semana", systemImage: "calendar") }
                    } label: {
                        HStack { Label("Atualizar página", systemImage: "arrow.clockwise"); if isPublishing { Spacer(); ProgressView() } }
                    }.disabled(isPublishing)
                    Button(role: .destructive) { showConfirmUnpublish = true } label: {
                        Label("Despublicar", systemImage: "trash")
                    }.disabled(isPublishing)
                } else {
                    Menu {
                        Button { publishPage(scope: .all) } label: { Label("Tudo", systemImage: "tray.full") }
                        Button { publishPage(scope: .lastWeek) } label: { Label("Última semana (digest)", systemImage: "calendar") }
                    } label: {
                        HStack { Label("Publicar página", systemImage: "globe"); if isPublishing { Spacer(); ProgressView() } }
                    }
                    .disabled(isPublishing || publishedPosts.isEmpty)
                    .accessibilityIdentifier("publishPageButton")
                    if publishedPosts.isEmpty {
                        Text("Publique ao menos um post para gerar a página.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let err = publishError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Página pública")
            }
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
            if !savedArticles.isEmpty {
                Section("Artigos salvos") {
                    ForEach(savedArticles) { s in
                        NavigationLink {
                            SourceDetailView(source: s)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.title ?? s.rawInput).font(.subheadline).lineLimit(2)
                                if let j = s.journal {
                                    Text("\(j)\(s.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                                }
                                SourceBadge(tier: s.trustTier, retraction: s.retractionStatus)
                            }
                        }
                    }
                    .onDelete { idx in
                        let rm = idx.map { savedArticles[$0] }
                        for s in rm { context.delete(s) }
                        try? context.save()
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
        .sheet(isPresented: $showingAddSource) { AddSourceSheet(topic: topic, savedStandalone: true) }
        .sheet(isPresented: $showingCompose) { ComposePostView(topic: topic) }
        .sheet(isPresented: $showingDigest) { WeeklyDigestView(topic: topic) }
        .sheet(isPresented: $showShare) {
            if let url = publishedURL { PublishShareView(url: url, title: topic.title) }
        }
        .confirmationDialog("Despublicar esta página?", isPresented: $showConfirmUnpublish, titleVisibility: .visible) {
            Button("Despublicar", role: .destructive) { unpublishTopic() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O link sai do ar. Você pode publicar de novo depois.")
        }
        .task(id: topic.remoteID) { await refreshViews() }
    }

    private func publishPage(scope: PublishScope) {
        isPublishing = true
        publishError = nil
        Task {
            do {
                let result = try await PublishClient().publish(topic: topic, scope: scope)
                topic.remoteID = result.slug
                topic.syncStatus = .synced
                topic.updatedAt = Date()
                try? context.save()
                await refreshViews()
            } catch {
                publishError = (error as? PublishError)?.errorDescription ?? error.localizedDescription
            }
            isPublishing = false
        }
    }

    private func unpublishTopic() {
        guard let slug = topic.remoteID else { return }
        isPublishing = true
        publishError = nil
        Task {
            do {
                try await PublishClient().unpublish(slug: slug)
                topic.remoteID = nil
                topic.syncStatus = .pending
                topic.updatedAt = Date()
                try? context.save()
                views = nil
            } catch {
                publishError = (error as? PublishError)?.errorDescription ?? error.localizedDescription
            }
            isPublishing = false
        }
    }

    private func refreshViews() async {
        guard let slug = topic.remoteID else { views = nil; return }
        views = await PublishClient().views(forSlug: slug)
    }
}
