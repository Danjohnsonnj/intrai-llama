import Foundation

@MainActor
public final class ChatViewModel {
    private let sessionRepository: SessionRepository
    private let messageRepository: MessageRepository
    private let inferenceEngine: InferenceEngine

    public init(
        sessionRepository: SessionRepository,
        messageRepository: MessageRepository,
        inferenceEngine: InferenceEngine
    ) {
        self.sessionRepository = sessionRepository
        self.messageRepository = messageRepository
        self.inferenceEngine = inferenceEngine
    }
}
