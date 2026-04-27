import Foundation

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public enum MessageStatus: String, Codable, Sendable {
    case pending
    case streaming
    case complete
    case failed
    case cancelled
}

public struct GenerationOptions: Sendable {
    public var maxTokens: Int
    public var temperature: Double

    public init(maxTokens: Int = 512, temperature: Double = 0.7) {
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public enum IntraiError: Error, Sendable {
    case modelNotLoaded
    case modelLoadFailed(reason: String)
    case generationFailed(reason: String)
    case persistenceFailed(reason: String)
}

extension IntraiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No model is loaded."
        case .modelLoadFailed(let reason):
            return reason
        case .generationFailed(let reason):
            return reason
        case .persistenceFailed(let reason):
            return reason
        }
    }
}
