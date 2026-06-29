// SciNapse/Sources/Features/Sources/SourceDetailView.swift
import SwiftUI
import UIKit
import SciNapseKit

struct SourceDetailView: View {
    let source: Source
    @State private var shareItems: [Any]?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if source.retractionStatus != .none {
                    retractionBanner
                }

                Text(source.title ?? source.rawInput)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)

                if !source.authors.isEmpty {
                    Text(source.authors.joined(separator: ", "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                SourceBadge(tier: source.trustTier, retraction: source.retractionStatus)

                if let line = publicationLine {
                    Text(line).font(.callout).foregroundStyle(.secondary)
                }

                if source.isOpenAccess, let oa = source.oaURL, let url = URL(string: oa) {
                    Link(destination: url) {
                        Label("Ler em acesso aberto", systemImage: "lock.open")
                    }.font(.subheadline)
                }

                if let abstract = source.abstract, !abstract.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Resumo").font(.headline)
                        Text(abstract).font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let cit = source.formattedCitation, !cit.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Referência (Vancouver)").font(.headline)
                        Text(cit).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = cit
                            copied = true
                        } label: {
                            Label(copied ? "Copiado" : "Copiar referência",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                        }.font(.caption)
                    }
                }

                if let link = sourceLink {
                    Link(destination: link) {
                        Label("Abrir fonte", systemImage: "safari")
                    }.font(.subheadline)
                }

                if source.verificationState == .pending {
                    Text("Verificação pendente — sem conexão quando foi adicionada. Toque para re-verificar quando estiver online.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Artigo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { share() } label: { Image(systemName: "square.and.arrow.up") }
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ShareSheet(activityItems: items) }
        }
    }

    private var retractionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(retractionTitle).font(.subheadline.bold())
                if let d = source.retractionNoticeDOI {
                    Text("Aviso: \(d)").font(.caption2)
                }
            }
        }
        .foregroundStyle(.red)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var retractionTitle: String {
        let year = source.retractionDate.map { " (\(Calendar.current.component(.year, from: $0)))" } ?? ""
        switch source.retractionStatus {
        case .retracted: return "Artigo retratado\(year)"
        case .concern: return "Expressão de preocupação\(year)"
        case .correction: return "Artigo corrigido\(year)"
        case .none: return ""
        }
    }

    private var publicationLine: String? {
        var parts: [String] = []
        if let j = source.journal { parts.append(j) }
        if let y = source.year { parts.append(String(y)) }
        if let v = source.volume {
            var loc = v
            if let i = source.issue { loc += "(\(i))" }
            if let p = source.pages { loc += ":\(p)" }
            parts.append(loc)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var sourceLink: URL? {
        if let r = source.resolvedURL, let u = URL(string: r) { return u }
        if let d = source.normalizedDOI { return URL(string: "https://doi.org/\(d)") }
        return URL(string: source.rawInput)
    }

    @MainActor private func share() {
        var lines: [String] = []
        if let cit = source.formattedCitation { lines.append(cit) }
        else { lines.append(source.title ?? source.rawInput) }
        if source.retractionStatus != .none { lines.append("[RETRATADO]") }
        if let link = sourceLink { lines.append(link.absoluteString) }
        shareItems = [lines.joined(separator: "\n")]
    }
}
