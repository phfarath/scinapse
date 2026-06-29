import SwiftUI
import SwiftData
import SciNapseKit

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    let topic: Topic
    let savedStandalone: Bool
    var onFinish: ([Source]) -> Void = { _ in }

    @State private var input = ""
    @State private var queue: [Source] = []
    @State private var phase: Phase = .editing
    @State private var noneFound = false
    enum Phase { case editing, working, done }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $input)
                        .frame(minHeight: 90, maxHeight: 200)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("sourceInputField")
                        .onChange(of: input) { noneFound = false }
                } header: {
                    Text("Cole um ou vários DOIs, PMIDs ou links")
                } footer: {
                    Text("Pode colar uma lista inteira — eu separo e verifico um a um.")
                }
                if noneFound {
                    Text("Nenhum DOI, PMID ou link reconhecido no texto.")
                        .font(.footnote).foregroundStyle(.red)
                }
                if !queue.isEmpty {
                    Section("Fontes (\(queue.count))") {
                        ForEach(queue) { s in SourceQueueRow(source: s) }
                    }
                }
            }
            .navigationTitle(savedStandalone ? "Salvar artigos" : "Adicionar fontes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(phase == .done ? "Concluir" : "Verificar") { Task { await primary() } }
                        .accessibilityIdentifier("verifySourceButton")
                        .disabled((phase == .editing && input.trimmingCharacters(in: .whitespaces).isEmpty) || phase == .working)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cancel() } }
            }
            .interactiveDismissDisabled(phase == .working)
        }
    }

    private func primary() async {
        if phase == .done { onFinish(queue); dismiss(); return }
        let ids = IdentifierParser.extractAll(in: input)
        guard !ids.isEmpty else { noneFound = true; return }
        phase = .working
        queue = services.createSources(rawInputs: ids, topic: topic, savedStandalone: savedStandalone)
        for s in queue { await services.verify(s) }
        phase = .done
    }

    private func cancel() {
        if !savedStandalone { services.delete(queue) }
        dismiss()
    }
}

private struct SourceQueueRow: View {
    @Bindable var source: Source
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(source.title ?? source.rawInput).font(.subheadline).lineLimit(2)
                Spacer()
                if source.verificationState == .pending { ProgressView() }
            }
            if source.verificationState != .pending {
                SourceBadge(tier: source.trustTier, retraction: source.retractionStatus)
            }
        }
    }
}
