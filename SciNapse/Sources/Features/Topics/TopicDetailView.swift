import SwiftUI
import SwiftData
import SciNapseKit

struct TopicDetailView: View {
    @Bindable var topic: Topic
    @Environment(\.modelContext) private var context
    @State private var showingAddSource = false
    @State private var showingCompose = false
    @State private var showingDigest = false

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
    }
}
