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
                if state == .verifying {
                    HStack { ProgressView(); Text("Verificando…") }
                }
                if let s = previewSource {
                    Section("Pré-visualização") { SourcePreviewView(source: s) }
                }
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
        let id = await services.addSource(
            rawInput: input,
            topicID: topic.persistentModelID,
            postID: post?.persistentModelID,
            savedStandalone: post == nil
        )
        let ctx = ModelContext(services.container)
        previewSource = ctx.model(for: id) as? Source
        state = .done
    }
}
