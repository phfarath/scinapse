// SciNapse/Sources/Features/Posts/PostDetailView.swift
import SwiftUI
import SwiftData
import SciNapseKit

struct PostDetailView: View {
    let post: Post
    @Environment(\.modelContext) private var context
    @State private var shareItems: [Any]?
    @State private var isPublishing = false
    @State private var publishError: String?
    @State private var showShare = false
    @State private var stats: PageStats?
    @State private var showConfirmUnpublish = false

    private var publishedURL: URL? { post.remoteID.flatMap { PublishClient.publicURL(forSlug: $0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                publishCard
                Text(post.title).font(.largeTitle.bold())
                if let t = post.topic {
                    Text(t.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(post.body).font(.body)
                Divider()
                Text("Fontes").font(.title2.bold())
                ForEach(post.sources) { s in
                    NavigationLink {
                        SourceDetailView(source: s)
                    } label: {
                        SourcePreviewView(source: s)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                shareItems = PostShare.items(for: post)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityIdentifier("sharePostButton")
        }
        .sheet(
            isPresented: Binding(
                get: { shareItems != nil },
                set: { if !$0 { shareItems = nil } }
            )
        ) {
            if let items = shareItems {
                ShareSheet(activityItems: items)
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = publishedURL { PublishShareView(url: url, title: post.title) }
        }
        .confirmationDialog("Despublicar este post?", isPresented: $showConfirmUnpublish, titleVisibility: .visible) {
            Button("Despublicar", role: .destructive) { unpublishPost() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O link deste post sai do ar.")
        }
        .task(id: post.remoteID) { await refreshStats() }
    }

    @ViewBuilder private var publishCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = publishedURL {
                HStack {
                    Label("Página publicada", systemImage: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(Brand.tealDeep)
                    Spacer()
                }
                if let s = stats {
                    statsRow(s)
                }
                Link(destination: url) {
                    Text(url.absoluteString).font(.caption).lineLimit(1).truncationMode(.middle)
                }
                HStack(spacing: 18) {
                    Button { showShare = true } label: { Label("Compartilhar", systemImage: "square.and.arrow.up") }
                    Button { publishThisPost() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { showConfirmUnpublish = true } label: { Label("Despublicar", systemImage: "trash") }
                }
                .font(.caption).buttonStyle(.borderless).disabled(isPublishing)
            } else {
                Button { publishThisPost() } label: {
                    HStack { Label("Publicar este post", systemImage: "globe"); if isPublishing { Spacer(); ProgressView() } }
                }
                .buttonStyle(.borderedProminent).tint(Brand.blue).disabled(isPublishing)
            }
            if let err = publishError { Text(err).font(.caption).foregroundStyle(.red) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func statsRow(_ s: PageStats) -> some View {
        HStack(spacing: 14) {
            Label("\(s.views)", systemImage: "eye")
            Label("\(s.useful)", systemImage: "hand.thumbsup")
            Label("\(s.notUseful)", systemImage: "hand.thumbsdown")
            Label("\(s.sourceClicks)", systemImage: "link")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func publishThisPost() {
        isPublishing = true; publishError = nil
        Task {
            do {
                let result = try await PublishClient().publish(post: post)
                post.remoteID = result.slug
                post.syncStatus = .synced
                post.updatedAt = Date()
                try? context.save()
                await refreshStats()
            } catch {
                publishError = (error as? PublishError)?.errorDescription ?? error.localizedDescription
            }
            isPublishing = false
        }
    }

    private func unpublishPost() {
        guard let slug = post.remoteID else { return }
        isPublishing = true; publishError = nil
        Task {
            do {
                try await PublishClient().unpublish(slug: slug)
                post.remoteID = nil
                post.syncStatus = .pending
                post.updatedAt = Date()
                try? context.save()
                stats = nil
            } catch {
                publishError = (error as? PublishError)?.errorDescription ?? error.localizedDescription
            }
            isPublishing = false
        }
    }

    private func refreshStats() async {
        guard let slug = post.remoteID else { stats = nil; return }
        stats = await PublishClient().stats(forSlug: slug)
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
