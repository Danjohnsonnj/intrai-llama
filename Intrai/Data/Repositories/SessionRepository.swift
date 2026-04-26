import Foundation

public protocol SessionRepository: Sendable {
    func createSession(title: String?) async throws -> ChatSessionRecord
    func renameSession(id: UUID, title: String) async throws
    func deleteSession(id: UUID) async throws
    func listSessions() async throws -> [ChatSessionRecord]
}
