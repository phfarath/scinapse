// SciNapse/Sources/Features/Posts/PostDetailView.swift
import SwiftUI
import SciNapseKit

struct PostDetailView: View {
    let post: Post
    @State private var shareItems: [Any]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(post.title).font(.largeTitle.bold())
                if let t = post.topic {
                    Text(t.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(post.body).font(.body)
                Divider()
                Text("Fontes").font(.title2.bold())
                ForEach(post.sources) { s in
                    SourcePreviewView(source: s).padding(.vertical, 4)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                shareItems = PostShare.items(for: post)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityIdentifier("sharePostButton")
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

enum PostShare {
    static func text(for post: Post) -> String {
        var lines = ["# \(post.title)", "", post.body, "", "## Fontes"]
        for s in post.sources {
            let cit = s.formattedCitation ?? (s.title ?? s.rawInput)
            let flag = s.retractionStatus == .none ? "" : " [RETRATADO]"
            lines.append("- \(cit)\(flag)")
        }
        return lines.joined(separator: "\n")
    }

    static func items(for post: Post) -> [Any] { [text(for: post)] }
}
