import Foundation

extension ChatSessionEntity {
    func toRecord() -> ChatSessionRecord {
        ChatSessionRecord(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension ChatMessageEntity {
    func toRecord() throws -> ChatMessageRecord {
        guard let sessionID = session?.id else {
            throw IntraiError.persistenceFailed(reason: "Message is missing session relationship")
        }

        guard let role = MessageRole(rawValue: roleRaw) else {
            throw IntraiError.persistenceFailed(reason: "Unknown message role '\(roleRaw)'")
        }

        guard let status = MessageStatus(rawValue: statusRaw) else {
            throw IntraiError.persistenceFailed(reason: "Unknown message status '\(statusRaw)'")
        }

        return ChatMessageRecord(
            id: id,
            sessionID: sessionID,
            role: role,
            content: content,
            status: status,
            createdAt: createdAt
        )
    }
}
