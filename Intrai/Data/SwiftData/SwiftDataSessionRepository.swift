import Foundation
import SwiftData

public actor SwiftDataSessionRepository: SessionRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func createSession(title: String?) async throws -> ChatSessionRecord {
        let now = Date()
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let session = ChatSessionEntity(
            title: trimmedTitle.isEmpty ? "New Chat" : trimmedTitle,
            createdAt: now,
            updatedAt: now
        )

        context.insert(session)
        try save()

        return session.toRecord()
    }

    public func renameSession(id: UUID, title: String) async throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw IntraiError.persistenceFailed(reason: "Session title cannot be empty")
        }

        guard let session = try fetchSession(id: id) else {
            throw IntraiError.persistenceFailed(reason: "Session not found")
        }

        session.title = normalizedTitle
        session.updatedAt = Date()
        try save()
    }

    public func deleteSession(id: UUID) async throws {
        guard let session = try fetchSession(id: id) else {
            return
        }

        context.delete(session)
        try save()
    }

    public func listSessions() async throws -> [ChatSessionRecord] {
        let descriptor = FetchDescriptor<ChatSessionEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let sessions = try context.fetch(descriptor)
        return sessions.map { $0.toRecord() }
    }

    private func fetchSession(id: UUID) throws -> ChatSessionEntity? {
        var descriptor = FetchDescriptor<ChatSessionEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw IntraiError.persistenceFailed(reason: "Failed to save session changes: \(error.localizedDescription)")
        }
    }
}
