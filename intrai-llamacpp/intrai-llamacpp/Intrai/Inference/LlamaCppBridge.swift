import Foundation

nonisolated public protocol LlamaCppBridge: Sendable {
    func loadModel(path: String) throws
    func unloadModel()
    func estimateTokenCount(for prompt: String) throws -> Int
    func currentContextLimit() -> Int
    func startGeneration(prompt: String, options: GenerationOptions) throws
    func nextTokenChunk() throws -> String?
    func cancelGeneration()
}
