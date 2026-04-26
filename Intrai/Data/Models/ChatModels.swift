import Foundation

public struct ChatSessionRecord: Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ChatMessageRecord: Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let role: MessageRole
    public var content: String
    public var status: MessageStatus
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        role: MessageRole,
        content: String,
        status: MessageStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.status = status
        self.createdAt = createdAt
    }
}
