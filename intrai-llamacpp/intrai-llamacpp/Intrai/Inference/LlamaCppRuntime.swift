import Foundation

#if canImport(llama)
import llama

nonisolated public final class LlamaCppRuntime: @unchecked Sendable, LlamaCppBridge {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var shouldCancel = false

    public init() {}

    deinit {
        unloadModel()
        llama_backend_free()
    }

    public func loadModel(path: String) throws {
        unloadModel()
        shouldCancel = false

        llama_backend_init()

        var modelParams = llama_model_default_params()
#if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
#endif

        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw IntraiError.modelLoadFailed(reason: "Unable to load model at \(path)")
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048

        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        contextParams.n_threads = Int32(nThreads)
        contextParams.n_threads_batch = Int32(nThreads)

        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw IntraiError.modelLoadFailed(reason: "Unable to initialize llama context")
        }

        model = loadedModel
        context = loadedContext
    }

    public func unloadModel() {
        if let currentContext = context {
            llama_free(currentContext)
            context = nil
        }

        if let currentModel = model {
            llama_model_free(currentModel)
            model = nil
        }
    }

    public func startGeneration(prompt: String, options: GenerationOptions) throws {
        guard context != nil, model != nil else {
            throw IntraiError.modelNotLoaded
        }
        _ = prompt
        _ = options
        shouldCancel = false
        // Tokenization/sampling loop is intentionally added in a later pass.
    }

    public func nextTokenChunk() throws -> String? {
        guard context != nil else {
            throw IntraiError.modelNotLoaded
        }

        if shouldCancel {
            return nil
        }

        // Placeholder behavior while generation loop is implemented incrementally.
        return nil
    }

    public func cancelGeneration() {
        shouldCancel = true
    }
}

#else

nonisolated public final class LlamaCppRuntime: @unchecked Sendable, LlamaCppBridge {
    public init() {}

    public func loadModel(path: String) throws {
        _ = path
        throw IntraiError.modelLoadFailed(
            reason: "llama.xcframework is not linked. Add framework and ensure module name is 'llama'."
        )
    }

    public func unloadModel() {}

    public func startGeneration(prompt: String, options: GenerationOptions) throws {
        _ = prompt
        _ = options
        throw IntraiError.modelNotLoaded
    }

    public func nextTokenChunk() throws -> String? {
        nil
    }

    public func cancelGeneration() {}
}

#endif
