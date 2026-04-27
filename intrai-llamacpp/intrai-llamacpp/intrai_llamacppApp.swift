import SwiftUI
import SwiftData

@main
struct IntraiApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try IntraiModelContainerFactory.makeModelContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentWrapper()
                .modelContainer(modelContainer)
        }
    }
}

private struct ContentWrapper: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ChatRootView(
            viewModel: AppComposition.makeChatViewModel(modelContext: modelContext)
        )
    }
}
