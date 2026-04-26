import Foundation
import SwiftData

public actor SwiftDataMessageRepository: MessageRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func appendUserMessage(sessionID: UUID, content: String) async throws -> ChatMessageRecord {
        let message = try createMessage(
            sessionID: sessionID,
            role: .user,
            content: content,
            status: .complete
        )
        return try message.toRecord()
    }

    public func appendAssistantPlaceholder(sessionID: UUID) async throws -> ChatMessageRecord {
        let message = try createMessage(
            sessionID: sessionID,
            role: .assistant,
            content: "",
            status: .streaming
        )
        return try message.toRecord()
    }

    public func appendAssistantChunk(messageID: UUID, chunk: String) async throws {
        guard let message = try fetchMessage(id: messageID) else {
            throw IntraiError.persistenceFailed(reason: "Assistant message not found")
        }

        message.content += chunk
        message.statusRaw = MessageStatus.streaming.rawValue

        if let session = message.session {
            session.updatedAt = Date()
        }

        try save()
    }

    public func markMessageFailed(messageID: UUID, reason: String) async throws {
        guard let message = try fetchMessage(id: messageID) else {
            throw IntraiError.persistenceFailed(reason: "Assistant message not found")
        }

        message.statusRaw = MessageStatus.failed.rawValue
        message.errorReason = reason
        if let session = message.session {
            session.updatedAt = Date()
        }
        try save()
    }

    public func markMessageCancelled(messageID: UUID) async throws {
        guard let message = try fetchMessage(id: messageID) else {
            throw IntraiError.persistenceFailed(reason: "Assistant message not found")
        }

        message.statusRaw = MessageStatus.cancelled.rawValue
        if let session = message.session {
            session.updatedAt = Date()
        }
        try save()
    }

    public func markMessageComplete(messageID: UUID) async throws {
        guard let message = try fetchMessage(id: messageID) else {
            throw IntraiError.persistenceFailed(reason: "Assistant message not found")
        }

        message.statusRaw = MessageStatus.complete.rawValue
        if let session = message.session {
            session.updatedAt = Date()
        }
        try save()
    }

    public func listMessages(sessionID: UUID) async throws -> [ChatMessageRecord] {
        let descriptor = FetchDescriptor<ChatMessageEntity>(
            predicate: #Predicate { $0.session?.id == sessionID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        let messages = try context.fetch(descriptor)
        return try messages.map { try $0.toRecord() }
    }

    private func createMessage(
        sessionID: UUID,
        role: MessageRole,
        content: String,
        status: MessageStatus
    ) throws -> ChatMessageEntity {
        guard let session = try fetchSession(id: sessionID) else {
            throw IntraiError.persistenceFailed(reason: "Session not found")
        }

        let message = ChatMessageEntity(
            roleRaw: role.rawValue,
            content: content,
            statusRaw: status.rawValue,
            session: session
        )

        context.insert(message)
        session.updatedAt = Date()
        try save()
        return message
    }

    private func fetchSession(id: UUID) throws -> ChatSessionEntity? {
        var descriptor = FetchDescriptor<ChatSessionEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchMessage(id: UUID) throws -> ChatMessageEntity? {
        var descriptor = FetchDescriptor<ChatMessageEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw IntraiError.persistenceFailed(reason: "Failed to save message changes: \(error.localizedDescription)")
        }
    }
}
