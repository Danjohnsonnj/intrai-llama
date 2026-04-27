import Foundation

nonisolated public protocol InferenceEngine: Sendable {
    func loadModel(from modelURL: URL) async throws
    func unloadModel() async
    func generateStream(
        prompt: String,
        options: GenerationOptions
    ) async -> AsyncThrowingStream<String, Error>
    func cancelGeneration() async
}
