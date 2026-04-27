import Foundation

public actor LlamaCppInferenceEngine: InferenceEngine {
    private let bridge: LlamaCppBridge
    private var isGenerating = false

    public init(bridge: LlamaCppBridge = LlamaCppRuntime()) {
        self.bridge = bridge
    }

    public func loadModel(from modelURL: URL) async throws {
        try bridge.loadModel(path: modelURL.path)
    }

    public func unloadModel() async {
        bridge.unloadModel()
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

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                isGenerating = false
            }

            continuation.onTermination = { _ in
                generationTask.cancel()
            }
        }
    }

    public func cancelGeneration() async {
        bridge.cancelGeneration()
    }
}
