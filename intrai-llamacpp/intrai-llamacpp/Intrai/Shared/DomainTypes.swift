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

public enum GenerationPhase: Sendable {
    case idle
    case preparing
    case waitingForFirstToken
    case streaming
}

public enum ContextFidelityState: String, Sendable {
    case normal
    case nearLimit
    case compactedSummaryActive
    case blocked
}

public enum MonitoringHealthState: String, Sendable {
    case healthy
    case slow
    case compacted
    case cancelled
    case failed
    case contextLimited
}

public enum GenerationPath: String, Sendable {
    case cold
    case warm
}

public enum TokenBudgetPressure: String, Sendable {
    case normal
    case warning
    case compacting
    case blocked
}

public struct TokenBudgetResult: Sendable {
    public let contextWindow: Int
    public let inputBudget: Int
    public let estimatedInputTokens: Int
    public let maxOutputTokens: Int
    public let safetyMargin: Int
    public let utilization: Double
    public let pressure: TokenBudgetPressure

    public init(
        contextWindow: Int,
        inputBudget: Int,
        estimatedInputTokens: Int,
        maxOutputTokens: Int,
        safetyMargin: Int,
        utilization: Double,
        pressure: TokenBudgetPressure
    ) {
        self.contextWindow = contextWindow
        self.inputBudget = inputBudget
        self.estimatedInputTokens = estimatedInputTokens
        self.maxOutputTokens = maxOutputTokens
        self.safetyMargin = safetyMargin
        self.utilization = utilization
        self.pressure = pressure
    }
}

public struct GenerationMonitoringSnapshot: Sendable {
    public let phase: GenerationPhase
    public let elapsedMs: Double
    public let streamedCharacterCount: Int
    public let approxCharsPerSecond: Double?

    public init(
        phase: GenerationPhase,
        elapsedMs: Double,
        streamedCharacterCount: Int,
        approxCharsPerSecond: Double?
    ) {
        self.phase = phase
        self.elapsedMs = elapsedMs
        self.streamedCharacterCount = streamedCharacterCount
        self.approxCharsPerSecond = approxCharsPerSecond
    }
}

public struct TokenBudgetPolicy: Sendable {
    public let maxOutputTokens: Int
    public let safetyMargin: Int
    public let warningThreshold: Double
    public let compactionThreshold: Double
    public let blockThreshold: Double

    public init(
        maxOutputTokens: Int = 512,
        safetyMargin: Int = 192,
        warningThreshold: Double = 0.80,
        compactionThreshold: Double = 0.90,
        blockThreshold: Double = 0.98
    ) {
        self.maxOutputTokens = max(1, maxOutputTokens)
        self.safetyMargin = max(0, safetyMargin)
        self.warningThreshold = warningThreshold
        self.compactionThreshold = compactionThreshold
        self.blockThreshold = blockThreshold
    }

    public func evaluate(contextWindow: Int, estimatedInputTokens: Int) -> TokenBudgetResult {
        let inputBudget = max(1, contextWindow - maxOutputTokens - safetyMargin)
        let utilization = min(5.0, Double(estimatedInputTokens) / Double(inputBudget))
        let pressure: TokenBudgetPressure
        if utilization >= blockThreshold {
            pressure = .blocked
        } else if utilization >= compactionThreshold {
            pressure = .compacting
        } else if utilization >= warningThreshold {
            pressure = .warning
        } else {
            pressure = .normal
        }

        return TokenBudgetResult(
            contextWindow: contextWindow,
            inputBudget: inputBudget,
            estimatedInputTokens: estimatedInputTokens,
            maxOutputTokens: maxOutputTokens,
            safetyMargin: safetyMargin,
            utilization: utilization,
            pressure: pressure
        )
    }
}

public enum IntraiError: Error, Sendable {
    case modelNotLoaded
    case modelLoadFailed(reason: String)
    case generationFailed(reason: String)
    case contextLimitReached(reason: String)
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
        case .contextLimitReached(let reason):
            return reason
        case .persistenceFailed(let reason):
            return reason
        }
    }
}
