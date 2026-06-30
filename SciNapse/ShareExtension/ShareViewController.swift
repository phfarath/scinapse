import UIKit
import UniformTypeIdentifiers

/// Share Extension: recebe um link (ou texto) compartilhado de outro app,
/// abre o SciNapse via deep link `scinapse://share?text=...` e encerra.
/// Sem App Group — funciona com conta Apple gratuita.
final class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await run() }
    }

    private func run() async {
        let text = await extractSharedText()
        openHost(with: text)
    }

    private func extractSharedText() async -> String? {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments, !providers.isEmpty else { return nil }
        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }),
           let data = try? await p.loadItem(forTypeIdentifier: urlType) {
            return (data as? URL)?.absoluteString ?? (data as? String)
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }),
           let data = try? await p.loadItem(forTypeIdentifier: textType) {
            return data as? String
        }
        return nil
    }

    private func openHost(with text: String?) {
        guard let text,
              let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "scinapse://share?text=\(encoded)") else {
            finish()
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
