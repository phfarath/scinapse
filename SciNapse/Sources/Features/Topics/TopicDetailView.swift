// SciNapse/Sources/Features/Topics/TopicDetailView.swift
import SwiftUI
import SwiftData
import SciNapseKit

struct TopicDetailView: View {
    @Bindable var topic: Topic
    @State private var showingAddSource = false
    @State private var showingCompose = false
    @State private var showingDigest = false

    private var publishedPosts: [Post] {
        topic.posts
            .filter { $0.status == .published }
            .sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }
    }

    var body: some View {
        List {
            Section("Posts") {
                if publishedPosts.isEmpty {
                    Text("Sem posts ainda").foregroundStyle(.secondary)
                }
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
