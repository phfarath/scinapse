import Foundation
import SwiftData
import SciNapseKit

@MainActor
final class AppServices: ObservableObject {
    let container: ModelContainer
    let resolver: any MetadataResolving
    private let writer: SourceWriter

    init(container: ModelContainer, resolver: any MetadataResolving) {
        self.container = container
        self.resolver = resolver
        self.writer = SourceWriter(context: container.mainContext, resolver: resolver)
    }

    func createSources(rawInputs: [String], topic: Topic, savedStandalone: Bool) -> [Source] {
        writer.createSources(rawInputs: rawInputs, topic: topic, savedStandalone: savedStandalone)
    }
    func verify(_ source: Source) async { await writer.verify(source) }
    func delete(_ sources: [Source]) { writer.delete(sources) }
}
