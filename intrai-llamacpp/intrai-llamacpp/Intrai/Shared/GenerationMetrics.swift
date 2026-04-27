import Foundation

public enum GenerationEndReason: String, Sendable {
    case completed
    case cancelled
    case failed
    case contextLimited
}

public struct GenerationMetrics: Sendable {
    public let promptID: UUID
    public let sessionID: UUID
    public let startedAt: Date
    public let timeToFirstTokenMs: Double?
    public let generationDurationMs: Double
    public let streamedCharacterCount: Int
    public let inputTokenEstimate: Int?
    public let contextUtilization: Double?
    public let compactionApplied: Bool
    public let generationPath: GenerationPath
    public let preflightDurationMs: Double?
    public let promptAssemblyDurationMs: Double?
    public let tokenEvaluationDurationMs: Double?
    public let engineQueueDurationMs: Double?
    public let decodeToFirstChunkMs: Double?
    public let forcedRecapCompactionApplied: Bool
    public let recapIntentMatched: Bool
    public let preflightHistoryTruncatedForSafety: Bool
    public let wasCancelled: Bool
    public let generationFailed: Bool
    public let endReason: GenerationEndReason

    public init(
        promptID: UUID,
        sessionID: UUID,
        startedAt: Date,
        timeToFirstTokenMs: Double?,
        generationDurationMs: Double,
        streamedCharacterCount: Int,
        inputTokenEstimate: Int?,
        contextUtilization: Double?,
        compactionApplied: Bool,
        generationPath: GenerationPath,
        preflightDurationMs: Double?,
        promptAssemblyDurationMs: Double?,
        tokenEvaluationDurationMs: Double?,
        engineQueueDurationMs: Double?,
        decodeToFirstChunkMs: Double?,
        forcedRecapCompactionApplied: Bool,
        recapIntentMatched: Bool,
        preflightHistoryTruncatedForSafety: Bool,
        wasCancelled: Bool,
        generationFailed: Bool,
        endReason: GenerationEndReason
    ) {
        self.promptID = promptID
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.generationDurationMs = generationDurationMs
        self.streamedCharacterCount = streamedCharacterCount
        self.inputTokenEstimate = inputTokenEstimate
        self.contextUtilization = contextUtilization
        self.compactionApplied = compactionApplied
        self.generationPath = generationPath
        self.preflightDurationMs = preflightDurationMs
        self.promptAssemblyDurationMs = promptAssemblyDurationMs
        self.tokenEvaluationDurationMs = tokenEvaluationDurationMs
        self.engineQueueDurationMs = engineQueueDurationMs
        self.decodeToFirstChunkMs = decodeToFirstChunkMs
        self.forcedRecapCompactionApplied = forcedRecapCompactionApplied
        self.recapIntentMatched = recapIntentMatched
        self.preflightHistoryTruncatedForSafety = preflightHistoryTruncatedForSafety
        self.wasCancelled = wasCancelled
        self.generationFailed = generationFailed
        self.endReason = endReason
    }
}

nonisolated public protocol MetricsRecorder: Sendable {
    func recordGeneration(_ metrics: GenerationMetrics) async
}

public actor InMemoryMetricsRecorder: MetricsRecorder {
    private(set) var generations: [GenerationMetrics] = []

    public init() {}

    public func recordGeneration(_ metrics: GenerationMetrics) async {
        generations.append(metrics)
    }
}

nonisolated public struct ConsoleMetricsRecorder: MetricsRecorder {
    public init() {}

    public func recordGeneration(_ metrics: GenerationMetrics) async {
        print(
            """
            [IntraiMetrics] session=\(metrics.sessionID) prompt=\(metrics.promptID) \
            ttftMs=\(metrics.timeToFirstTokenMs.map { String(format: "%.2f", $0) } ?? "nil") \
            durationMs=\(String(format: "%.2f", metrics.generationDurationMs)) \
            chars=\(metrics.streamedCharacterCount) \
            inputTokens=\(metrics.inputTokenEstimate.map(String.init) ?? "nil") \
            contextUtil=\(metrics.contextUtilization.map { String(format: "%.3f", $0) } ?? "nil") \
            path=\(metrics.generationPath.rawValue) \
            preflightMs=\(metrics.preflightDurationMs.map { String(format: "%.2f", $0) } ?? "nil") \
            assembleMs=\(metrics.promptAssemblyDurationMs.map { String(format: "%.2f", $0) } ?? "nil") \
            tokenEvalMs=\(metrics.tokenEvaluationDurationMs.map { String(format: "%.2f", $0) } ?? "nil") \
            engineQueueMs=\(metrics.engineQueueDurationMs.map { String(format: "%.2f", $0) } ?? "nil") \
            decodeToFirstMs=\(metrics.decodeToFirstChunkMs.map { String(format: "%.2f", $0) } ?? "nil") \
            forcedRecap=\(metrics.forcedRecapCompactionApplied) \
            recapIntent=\(metrics.recapIntentMatched) \
            historyTruncated=\(metrics.preflightHistoryTruncatedForSafety) \
            compacted=\(metrics.compactionApplied) cancelled=\(metrics.wasCancelled) failed=\(metrics.generationFailed) \
            endReason=\(metrics.endReason.rawValue)
            """
        )
    }
}
