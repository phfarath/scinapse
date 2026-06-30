// SciNapse/Sources/App/ScinapseApp.swift
import SwiftUI
import SwiftData
import SciNapseKit

@main
struct ScinapseApp: App {
    let container: ModelContainer
    @StateObject private var services: AppServices
    @StateObject private var shareInbox = ShareInbox()

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITestInMemory")
        let c = try! ModelContainerFactory.make(inMemory: inMemory)
        self.container = c
        let useStub = ProcessInfo.processInfo.arguments.contains("-UITestStubVerification")
        let resolver: any MetadataResolving = useStub ? UITestResolver() : MetadataService()
        _services = StateObject(wrappedValue: AppServices(container: c, resolver: resolver))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(services)
                .environmentObject(shareInbox)
                .onOpenURL { shareInbox.handle(url: $0) }
        }
        .modelContainer(container)
    }
}
