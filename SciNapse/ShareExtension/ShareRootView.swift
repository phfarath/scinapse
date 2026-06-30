import SwiftUI
import SwiftData
import SciNapseKit

struct ShareRootView: View {
    let sharedText: String
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.createdAt, order: .reverse) private var topics: [Topic]

    @State private var selectedTopicID: PersistentIdentifier?
    @State private var newTopicName = ""
    @State private var queue: [Source] = []
    @State private var phase: Phase = .choosing
    enum Phase { case choosing, working, done }

    private let resolver: any MetadataResolving = MetadataService()
    private var ids: [String] { IdentifierParser.extractAll(in: sharedText) }

    private var canProceed: Bool {
        if phase == .done { return true }
        if phase == .working { return false }
        if ids.isEmpty { return false }
        return selectedTopicID != nil || !newTopicName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Conteúdo recebido") {
                    Text(sharedText).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    if ids.isEmpty {
                        Text("Nenhum DOI, PMID ou link reconhecido.").font(.footnote).foregroundStyle(.red)
                    } else {
                        Text("\(ids.count) fonte(s) detectada(s)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if phase == .choosing && !ids.isEmpty {
                    Section("Salvar no tópico") {
                        ForEach(topics) { t in
                            Button {
                                selectedTopicID = t.persistentModelID
                                newTopicName = ""
                            } label: {
                                HStack {
                                    Text(t.title)
                                    Spacer()
                                    if selectedTopicID == t.persistentModelID {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                        TextField("Ou crie um novo tópico…", text: $newTopicName)
                            .onChange(of: newTopicName) { if !newTopicName.isEmpty { selectedTopicID = nil } }
                    }
                }
                if !queue.isEmpty {
                    Section("Fontes (\(queue.count))") {
                        ForEach(queue) { s in ShareSourceRow(source: s) }
                    }
                }
            }
            .navigationTitle("Salvar no SciNapse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(phase == .done ? "Concluir" : "Adicionar") { Task { await primary() } }
                        .disabled(!canProceed)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { onDone() } }
            }
            .interactiveDismissDisabled(phase == .working)
        }
    }

    private func primary() async {
        if phase == .done { onDone(); return }
        let topic = resolveTopic()
        phase = .working
        let writer = SourceWriter(context: context, resolver: resolver)
        queue = writer.createSources(rawInputs: ids, topic: topic, savedStandalone: true)
        for s in queue { await writer.verify(s) }
        phase = .done
    }

    private func resolveTopic() -> Topic {
        if let id = selectedTopicID, let t = context.model(for: id) as? Topic { return t }
        let name = newTopicName.trimmingCharacters(in: .whitespaces)
        let t = Topic(title: name.isEmpty ? "Compartilhados" : name)
        context.insert(t)
        try? context.save()
        return t
    }
}

private struct ShareSourceRow: View {
    @Bindable var source: Source
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(source.title ?? source.rawInput).font(.subheadline).lineLimit(2)
                Spacer()
                if source.verificationState == .pending { ProgressView() }
            }
            if source.verificationState != .pending {
                ShareSourceBadge(tier: source.trustTier, retraction: source.retractionStatus)
            }
        }
    }
}
