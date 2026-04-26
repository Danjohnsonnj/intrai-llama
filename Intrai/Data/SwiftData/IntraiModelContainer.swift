import Foundation
import SwiftData

public enum IntraiModelContainerFactory {
    public static func makeModelContainer(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
