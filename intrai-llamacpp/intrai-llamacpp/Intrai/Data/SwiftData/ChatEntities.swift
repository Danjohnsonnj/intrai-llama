import Foundation
import SwiftData

@Model
public final class ChatSessionEntity {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessageEntity.session)
    public var messages: [ChatMessageEntity]

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
        self.messages = []
    }
}

@Model
public final class ChatMessageEntity {
    @Attribute(.unique) public var id: UUID
    public var roleRaw: String
    public var content: String
    public var statusRaw: String
    public var createdAt: Date
    public var errorReason: String?

    public var session: ChatSessionEntity?

    public init(
        id: UUID = UUID(),
        roleRaw: String,
        content: String,
        statusRaw: String,
        createdAt: Date = Date(),
        errorReason: String? = nil,
        session: ChatSessionEntity? = nil
    ) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.errorReason = errorReason
        self.session = session
    }
}
