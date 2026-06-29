import Foundation
import SwiftData
import SciNapseKit

@MainActor
final class AppServices: ObservableObject {
    let container: ModelContainer
    let resolver: any MetadataResolving

    init(container: ModelContainer, resolver: any MetadataResolving) {
        self.container = container
        self.resolver = resolver
    }

    private var context: ModelContext { container.mainContext }

    /// Cria as Sources (estado .pending) no contexto principal e as devolve.
    func createSources(rawInputs: [String], topic: Topic, savedStandalone: Bool) -> [Source] {
        var created: [Source] = []
        for raw in rawInputs {
            let s = Source(rawInput: raw, kind: IdentifierParser.kind(for: raw))
            s.savedStandalone = savedStandalone
            s.topic = topic
            context.insert(s)
            created.append(s)
        }
        try? context.save()
        return created
    }

    /// Verifica uma fonte (rede) e atualiza no contexto principal — a UI observa.
    func verify(_ source: Source) async {
        do {
            let result = try await resolver.verify(source.rawInput)
            source.apply(result)
        } catch let error as AppError where error == .offline {
            source.markPendingOffline()
        } catch {
            source.markFailed()
        }
        source.updatedAt = Date()
        try? context.save()
    }

    func delete(_ sources: [Source]) {
        for s in sources { context.delete(s) }
        try? context.save()
    }
}
