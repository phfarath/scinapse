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
                    Label("Publicado", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Brand.tealDeep)
                    Link(destination: url) {
                        Text(url.absoluteString).font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                    Button { showShare = true } label: { Label("Compartilhar link", systemImage: "square.and.arrow.up") }
                    Button { publishPage() } label: {
                        HStack { Label("Atualizar página", systemImage: "arrow.clockwise"); if isPublishing { Spacer(); ProgressView() } }
                    }.disabled(isPublishing)
                } else {
                    Button { publishPage() } label: {
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
            if let url = publishedURL { ShareSheet(activityItems: [url]) }
        }
    }

    private func publishPage() {
        isPublishing = true
        publishError = nil
        Task {
            do {
                let result = try await PublishClient().publish(topic: topic)
                topic.remoteID = result.slug
                topic.syncStatus = .synced
                topic.updatedAt = Date()
                try? context.save()
            } catch {
                publishError = (error as? PublishError)?.errorDescription ?? error.localizedDescription
            }
            isPublishing = false
        }
    }
}
