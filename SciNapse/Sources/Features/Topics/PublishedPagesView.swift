// SciNapse/Sources/Features/Topics/PublishedPagesView.swift
// "Minhas páginas": todos os tópicos publicados, com views, atualizar, despublicar e compartilhar.
import SwiftUI
import SwiftData
import SciNapseKit

struct PublishedPagesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Topic> { $0.remoteID != nil }, sort: \Topic.updatedAt, order: .reverse)
    private var published: [Topic]

    @State private var views: [String: Int] = [:]
    @State private var shareTarget: ShareTarget?
    @State private var busySlug: String?
    @State private var errorText: String?

    struct ShareTarget: Identifiable { let id = UUID(); let url: URL; let title: String }

    var body: some View {
        List {
            if published.isEmpty {
                ContentUnavailableView("Nenhuma página publicada", systemImage: "globe",
                                       description: Text("Publique um tópico para ele aparecer aqui."))
            }
            ForEach(published) { topic in
                if let slug = topic.remoteID, let url = PublishClient.publicURL(forSlug: slug) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(topic.title).font(.headline)
                            Spacer()
                            if let v = views[slug] {
                                Label("\(v)", systemImage: "eye").font(.caption).foregroundStyle(.secondary)
                            }
                            if busySlug == slug { ProgressView() }
                        }
                        Link(destination: url) {
                            Text(url.absoluteString).font(.caption).foregroundStyle(.blue)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        HStack(spacing: 18) {
                            Button { shareTarget = ShareTarget(url: url, title: topic.title) } label: {
                                Label("Compartilhar", systemImage: "square.and.arrow.up")
                            }
                            Button { republish(topic) } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                            Button(role: .destructive) { unpublish(topic) } label: { Label("Despublicar", systemImage: "trash") }
                        }
                        .font(.caption).buttonStyle(.borderless).padding(.top, 2)
                        .disabled(busySlug == slug)
                    }
                    .padding(.vertical, 4)
                    .task(id: slug) { views[slug] = await PublishClient().views(forSlug: slug) }
                }
            }
            if let err = errorText { Text(err).font(.caption).foregroundStyle(.red) }
        }
        .navigationTitle("Minhas páginas")
        .sheet(item: $shareTarget) { t in PublishShareView(url: t.url, title: t.title) }
    }

    private func republish(_ topic: Topic) {
        guard let slug = topic.remoteID else { return }
        busySlug = slug; errorText = nil
        Task {
            do {
                _ = try await PublishClient().publish(topic: topic, scope: .all)
                topic.updatedAt = Date(); try? context.save()
                views[slug] = await PublishClient().views(forSlug: slug)
            } catch { errorText = (error as? PublishError)?.errorDescription ?? error.localizedDescription }
            busySlug = nil
        }
    }

    private func unpublish(_ topic: Topic) {
        guard let slug = topic.remoteID else { return }
        busySlug = slug; errorText = nil
        Task {
            do {
                try await PublishClient().unpublish(slug: slug)
                topic.remoteID = nil; topic.syncStatus = .pending; topic.updatedAt = Date()
                try? context.save()
            } catch { errorText = (error as? PublishError)?.errorDescription ?? error.localizedDescription }
            busySlug = nil
        }
    }
}
