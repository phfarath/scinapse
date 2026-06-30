import Foundation
import SwiftData

/// Cria e verifica fontes no contexto fornecido (usado pelo app e pelo Share Extension).
@MainActor
public final class SourceWriter {
    private let context: ModelContext
    private let resolver: any MetadataResolving

    public init(context: ModelContext, resolver: any MetadataResolving) {
        self.context = context
        self.resolver = resolver
    }

    public func createSources(rawInputs: [String], topic: Topic, savedStandalone: Bool) -> [Source] {
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

    public func verify(_ source: Source) async {
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

    public func delete(_ sources: [Source]) {
        for s in sources { context.delete(s) }
        try? context.save()
    }
}
