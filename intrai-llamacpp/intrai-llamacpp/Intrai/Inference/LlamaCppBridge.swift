import Foundation

nonisolated public protocol LlamaCppBridge: Sendable {
    func loadModel(path: String) throws
    func unloadModel()
    func startGeneration(prompt: String, options: GenerationOptions) throws
    func nextTokenChunk() throws -> String?
    func cancelGeneration()
}
