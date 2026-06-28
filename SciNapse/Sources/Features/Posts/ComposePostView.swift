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
                    TextField("Título do achado", text: $title)
                        .accessibilityIdentifier("postTitleField")
                }
                Section("Síntese") {
                    TextField("O que você descobriu…", text: $body_, axis: .vertical)
                        .lineLimit(4...10)
                        .accessibilityIdentifier("postBodyField")
                }
                Section("Fontes (mín. 1 para publicar)") {
                    ForEach(sources) { s in
                        HStack {
                            Text(s.title ?? s.rawInput).lineLimit(1)
                            Spacer()
                            SourceBadge(tier: s.trustTier, retraction: s.retractionStatus)
                        }
                    }
                    Button {
                        ensureDraft()
                        showingAddSource = true
                    } label: {
                        Label("Adicionar fonte", systemImage: "plus")
                    }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cancel() }
                }
            }
            .sheet(isPresented: $showingAddSource) {
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
        if let draft, draft.status == .draft {
            context.delete(draft)
            try? context.save()
        }
        dismiss()
    }
}
