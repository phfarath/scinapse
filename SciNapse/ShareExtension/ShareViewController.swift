import UIKit
import SwiftUI
import SwiftData
import SciNapseKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await setup() }
    }

    private func setup() async {
        let text = await extractSharedText() ?? ""
        guard let container = try? ModelContainerFactory.make(appGroupID: Config.appGroupID) else {
            finish(); return
        }
        let root = ShareRootView(sharedText: text, onDone: { [weak self] in self?.finish() })
            .modelContainer(container)
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
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

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
