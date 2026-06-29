import SwiftUI
import SwiftData
import SciNapseKit

struct ComposePostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let topic: Topic

    @State private var title = ""
    @State private var body_ = ""
    @State private var attachedSources: [Source] = []
    @State private var showingAddSource = false

    private var canPublish: Bool { PostComposer.canPublish(title: title, sourceCount: attachedSources.count) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Título") {
                    TextField("Título do achado", text: $title).accessibilityIdentifier("postTitleField")
                }
                Section("Síntese") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 140, maxHeight: 360)
                        .accessibilityIdentifier("postBodyField")
                }
                Section("Fontes (mín. 1 para publicar)") {
                    ForEach(attachedSources) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.title ?? s.rawInput).font(.subheadline).lineLimit(2)
                            SourceBadge(tier: s.trustTier, retraction: s.retractionStatus)
                        }
                    }
                    .onDelete { idx in
                        let toRemove = idx.map { attachedSources[$0] }
                        attachedSources.remove(atOffsets: idx)
                        context_delete(toRemove)
                    }
                    Button { showingAddSource = true } label: { Label("Adicionar fontes", systemImage: "plus") }
                        .accessibilityIdentifier("addSourceToPostButton")
                }
            }
            .navigationTitle("Novo post")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publicar") { publish() }.disabled(!canPublish).accessibilityIdentifier("publishButton")
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cancel() } }
            }
            .sheet(isPresented: $showingAddSource) {
                AddSourceSheet(topic: topic, savedStandalone: false) { newSources in
                    attachedSources.append(contentsOf: newSources)
                }
            }
        }
    }

    private func context_delete(_ sources: [Source]) { for s in sources { context.delete(s) }; try? context.save() }

    private func publish() {
        let post = Post(title: title.trimmingCharacters(in: .whitespaces), body: body_, status: .published)
        post.topic = topic
        post.publishedAt = Date()
        context.insert(post)
        for s in attachedSources { post.sources.append(s) }
        try? context.save()
        dismiss()
    }

    private func cancel() {
        context_delete(attachedSources)
        dismiss()
    }
}
