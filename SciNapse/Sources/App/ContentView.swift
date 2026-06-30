// SciNapse/Sources/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var shareInbox: ShareInbox

    var body: some View {
        TopicListView()
            .sheet(isPresented: Binding(
                get: { shareInbox.pendingText != nil },
                set: { if !$0 { shareInbox.pendingText = nil } }
            )) {
                if let text = shareInbox.pendingText {
                    ReceiveSharedSheet(sharedText: text)
                }
            }
    }
}
