import Foundation

public actor LlamaCppInferenceEngine: InferenceEngine {
    private let bridge: LlamaCppBridge
    private var isGenerating = false
    private var warmupCompletedForLoadedModel = false
    private var hasCompletedDecodeSession = false

    private let warmupPrompt = "Warmup run. Reply with OK."
    private let warmupOptions = GenerationOptions(maxTokens: 12, temperature: 0)

    public init(bridge: LlamaCppBridge = LlamaCppRuntime()) {
        self.bridge = bridge
    }

    public func loadModel(from modelURL: URL) async throws {
        try bridge.loadModel(path: modelURL.path)
        warmupCompletedForLoadedModel = false
        hasCompletedDecodeSession = false
        await runWarmupIfNeeded()
    }

    public func unloadModel() async {
        bridge.unloadModel()
        warmupCompletedForLoadedModel = false
        hasCompletedDecodeSession = false
    }

    public func estimateTokenCount(for prompt: String) async throws -> Int {
        try bridge.estimateTokenCount(for: prompt)
    }

    public func currentContextLimit() async -> Int {
        bridge.currentContextLimit()
    }

    public func generationPathForNextRequest() async -> GenerationPath {
        if warmupCompletedForLoadedModel || hasCompletedDecodeSession {
            return .warm
        }
        return .cold
    }

    public func generateStream(
        prompt: String,
        options: GenerationOptions
    ) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let generationTask = Task {
                if isGenerating {
                    continuation.finish(throwing: IntraiError.generationFailed(reason: "Generation already in progress"))
                    return
                }

                isGenerating = true
                defer {
                    isGenerating = false
                }

                do {
                    try bridge.startGeneration(prompt: prompt, options: options)

                    while true {
                        if Task.isCancelled {
                            bridge.cancelGeneration()
                            break
                        }

                        let chunk = try bridge.nextTokenChunk()
                        guard let chunk else {
                            break
                        }

                        if !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                    }

                    hasCompletedDecodeSession = true
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                generationTask.cancel()
            }
        }
    }

    public func cancelGeneration() async {
        bridge.cancelGeneration()
    }

    private func runWarmupIfNeeded() async {
        guard !warmupCompletedForLoadedModel else { return }
        do {
            try bridge.startGeneration(prompt: warmupPrompt, options: warmupOptions)
            while let _ = try bridge.nextTokenChunk() {
                if Task.isCancelled {
                    bridge.cancelGeneration()
                    return
                }
            }
            warmupCompletedForLoadedModel = true
        } catch {
            bridge.cancelGeneration()
            print("[IntraiWarmup] warmup failed: \(error.localizedDescription)")
        }
    }
}
