import Foundation

public struct GenerationMetrics: Sendable {
    public let promptID: UUID
    public let sessionID: UUID
    public let startedAt: Date
    public let timeToFirstTokenMs: Double?
    public let generationDurationMs: Double
    public let streamedCharacterCount: Int
    public let wasCancelled: Bool
    public let generationFailed: Bool

    public init(
        promptID: UUID,
        sessionID: UUID,
        startedAt: Date,
        timeToFirstTokenMs: Double?,
        generationDurationMs: Double,
        streamedCharacterCount: Int,
        wasCancelled: Bool,
        generationFailed: Bool
    ) {
        self.promptID = promptID
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.generationDurationMs = generationDurationMs
        self.streamedCharacterCount = streamedCharacterCount
        self.wasCancelled = wasCancelled
        self.generationFailed = generationFailed
    }
}

public protocol MetricsRecorder: Sendable {
    func recordGeneration(_ metrics: GenerationMetrics)
}

public actor InMemoryMetricsRecorder: MetricsRecorder {
    private(set) var generations: [GenerationMetrics] = []

    public init() {}

    public func recordGeneration(_ metrics: GenerationMetrics) {
        generations.append(metrics)
    }
}

public struct ConsoleMetricsRecorder: MetricsRecorder {
    public init() {}

    public func recordGeneration(_ metrics: GenerationMetrics) {
        print(
            """
            [IntraiMetrics] session=\(metrics.sessionID) prompt=\(metrics.promptID) \
            ttftMs=\(metrics.timeToFirstTokenMs.map { String(format: "%.2f", $0) } ?? "nil") \
            durationMs=\(String(format: "%.2f", metrics.generationDurationMs)) \
            chars=\(metrics.streamedCharacterCount) cancelled=\(metrics.wasCancelled) failed=\(metrics.generationFailed)
            """
        )
    }
}
