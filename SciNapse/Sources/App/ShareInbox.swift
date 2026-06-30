// SciNapse/Sources/App/ShareInbox.swift
import Foundation

/// Recebe o conteúdo vindo do Share Extension via deep link `scinapse://share?text=...`.
@MainActor
final class ShareInbox: ObservableObject {
    @Published var pendingText: String?

    func handle(url: URL) {
        guard url.scheme?.lowercased() == "scinapse" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // URLComponents já decodifica o percent-encoding dos query items.
        if let text = comps?.queryItems?.first(where: { $0.name == "text" })?.value,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingText = text
        }
    }
}
