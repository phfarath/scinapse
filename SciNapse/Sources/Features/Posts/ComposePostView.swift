import SwiftUI
import SwiftData
import SciNapseKit

struct ComposePostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var services: AppServices
    let topic: Topic

    @State private var title = ""
    @State private var body_ = ""
    @State private var attachedSources: [Source] = []
    @State private var showingAddSource = false
    @State private var pasteDraft: PastedPostDraft?
    @State private var pasteRaw = ""
    @State private var pasteDismissed = false
    @State private var separating = false

    private var canPublish: Bool { PostComposer.canPublish(title: title, sourceCount: attachedSources.count) }

    var body: some View {
        NavigationStack {
            Form {
                if let draft = pasteDraft {
                    pasteBanner(draft)
                }
                Section("Título") {
                    TextField("Título do achado", text: $title)
                        .accessibilityIdentifier("postTitleField")
                        .onChange(of: title) { _, new in handlePotentialPaste(new) }
                }
                Section("Síntese") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 140, maxHeight: 360)
                        .accessibilityIdentifier("postBodyField")
                        .onChange(of: body_) { _, new in handlePotentialPaste(new) }
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

    // MARK: - Colar do ChatGPT (separar em Título / Síntese / Fontes)

    @ViewBuilder
    private func pasteBanner(_ draft: PastedPostDraft) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Atualização com várias fontes detectada", systemImage: "wand.and.stars")
                    .font(.subheadline).bold()
                Text("Posso separar em Título e Síntese e extrair as fontes automaticamente para você revisar.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        Task { await applySeparation(draft) }
                    } label: {
                        if separating { ProgressView() } else { Text("Separar") }
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.blue)
                    .disabled(separating)
                    .accessibilityIdentifier("separatePasteButton")
                    Button("Ignorar") { pasteDismissed = true; pasteDraft = nil }
                        .disabled(separating)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Oferece separar quando um conteúdo estruturado (2+ fontes) aparece em
    /// qualquer um dos campos — tipicamente uma colagem, já que ninguém digita
    /// 2+ DOIs à mão. Funciona colando no Título ou na Síntese.
    private func handlePotentialPaste(_ text: String) {
        guard !separating else { return }
        if title.isEmpty && body_.isEmpty {   // campos limpos: reabre a oferta
            pasteDismissed = false
            pasteDraft = nil
            return
        }
        guard !pasteDismissed, pasteDraft == nil else { return }
        if PastedPostParser.looksStructured(text) {
            pasteRaw = text
            pasteDraft = PastedPostParser.parse(text)
        }
    }

    private func applySeparation(_ draft: PastedPostDraft) async {
        separating = true
        title = draft.title
        body_ = draft.body
        let ids = IdentifierParser.extractAllInProse(in: pasteRaw)
        if !ids.isEmpty {
            let created = services.createSources(rawInputs: ids, topic: topic, savedStandalone: false)
            attachedSources.append(contentsOf: created)
            for s in created { await services.verify(s) }
        }
        separating = false
        pasteDraft = nil
        pasteDismissed = true
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
