// SciNapse/Sources/Features/Digest/WeeklyDigestView.swift
import SwiftUI
import SciNapseKit

struct WeeklyDigestView: View {
    @Environment(\.dismiss) private var dismiss
    let topic: Topic
    @State private var shareItems: [Any]?

    private var model: DigestModel {
        DigestBuilder.build(topicTitle: topic.title, posts: topic.posts, now: Date(), days: 7)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DigestPageView(model: model).padding()
            }
            .navigationTitle("Digest da semana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { share() } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityIdentifier("shareDigestButton")
                        .disabled(model.items.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
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
        }
    }

    @MainActor private func share() {
        let currentModel = model
        let text = DigestTextRenderer.markdown(currentModel)
        let pageView = DigestPageView(model: currentModel).frame(width: 540)
        let pdf = PDFExporter.pdf(from: pageView, pageSize: CGSize(width: 595, height: 842))
        var items: [Any] = [text]
        if let url = PDFExporter.writeTempPDF(pdf, name: "digest.pdf") { items.append(url) }
        shareItems = items
    }
}

struct DigestPageView: View {
    let model: DigestModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.topicTitle).font(.title.bold())
            Text("Principais publicações da semana").font(.subheadline).foregroundStyle(.secondary)
            if model.items.isEmpty {
                Text("Nenhum post publicado neste período.").foregroundStyle(.secondary)
            }
            ForEach(model.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    Text(item.body).font(.body)
                    ForEach(item.citations, id: \.self) { c in
                        Text("• \(c)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
        }
    }
}
