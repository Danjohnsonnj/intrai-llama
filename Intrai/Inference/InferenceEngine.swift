import Foundation

public protocol InferenceEngine: Sendable {
    func loadModel(from modelURL: URL) async throws
    func unloadModel() async
    func generateStream(
        prompt: String,
        options: GenerationOptions
    ) -> AsyncThrowingStream<String, Error>
    func cancelGeneration() async
}
