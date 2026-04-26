import Foundation

public protocol MessageRepository: Sendable {
    func appendUserMessage(sessionID: UUID, content: String) async throws -> ChatMessageRecord
    func appendAssistantPlaceholder(sessionID: UUID) async throws -> ChatMessageRecord
    func appendAssistantChunk(messageID: UUID, chunk: String) async throws
    func markMessageFailed(messageID: UUID, reason: String) async throws
    func markMessageCancelled(messageID: UUID) async throws
    func markMessageComplete(messageID: UUID) async throws
    func listMessages(sessionID: UUID) async throws -> [ChatMessageRecord]
}
