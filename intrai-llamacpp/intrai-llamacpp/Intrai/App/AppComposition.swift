import Foundation
import SwiftData

/// Root dependency container for wiring feature modules to protocol implementations.
/// Concrete bindings are intentionally deferred until implementation steps.
public struct AppComposition {
    public init() {}

    public static func makeRepositories(
        modelContext: ModelContext
    ) -> (sessionRepository: SessionRepository, messageRepository: MessageRepository) {
        let sessionRepository = SwiftDataSessionRepository(context: modelContext)
        let messageRepository = SwiftDataMessageRepository(context: modelContext)
        return (sessionRepository, messageRepository)
    }

    @MainActor
    public static func makeChatViewModel(modelContext: ModelContext) -> ChatViewModel {
        let repositories = makeRepositories(modelContext: modelContext)
        let inferenceEngine = LlamaCppInferenceEngine()
        return ChatViewModel(
            sessionRepository: repositories.sessionRepository,
            messageRepository: repositories.messageRepository,
            inferenceEngine: inferenceEngine
        )
    }
}
