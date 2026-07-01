// SciNapse/Sources/Features/Topics/TopicListView.swift
import SwiftUI
import SwiftData
import SciNapseKit

struct TopicListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.createdAt, order: .reverse) private var topics: [Topic]
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(topics) { topic in
                    NavigationLink(value: topic.id) {
                        HStack(spacing: 12) {
                            Image(systemName: "books.vertical.fill")
                                .font(.title3)
                                .foregroundStyle(Brand.blue)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text(topic.title).font(.headline)
                                Text("\(topic.posts.count) posts").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationDestination(for: UUID.self) { id in
                if let topic = topics.first(where: { $0.id == id }) {
                    TopicDetailView(topic: topic)
                }
            }
            .navigationTitle("SciNapse")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if topics.isEmpty {
                    ContentUnavailableView("Nenhum tópico", systemImage: "tray", description: Text("Crie um tópico para começar"))
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { SciNapseWordmark() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("addTopicButton")
                }
            }
            .alert("Novo tópico", isPresented: $showingNew) {
                TextField("Nome", text: $newName).accessibilityIdentifier("topicNameField")
                Button("Salvar") { addTopic() }.accessibilityIdentifier("saveTopicButton")
                Button("Cancelar", role: .cancel) { newName = "" }
            }
        }
    }

    private func addTopic() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.insert(Topic(title: trimmed))
        try? context.save()
        newName = ""
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(topics[i]) }
        try? context.save()
    }
}
