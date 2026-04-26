import Foundation

/// Placeholder seam for direct `llama.cpp` XCFramework interop.
/// Concrete C API calls are added in the integration step.
public protocol LlamaCppBridge: Sendable {
    func loadModel(path: String) throws
    func unloadModel()
    func startGeneration(prompt: String, options: GenerationOptions) throws
    func nextTokenChunk() throws -> String?
    func cancelGeneration()
}
