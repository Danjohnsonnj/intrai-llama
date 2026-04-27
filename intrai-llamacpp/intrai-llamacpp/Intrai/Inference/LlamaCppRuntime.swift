import Foundation
import Darwin

#if canImport(llama)
import llama

nonisolated public final class LlamaCppRuntime: @unchecked Sendable, LlamaCppBridge {
    public struct RuntimeConfig: Sendable {
        let contextWindow: UInt32
        let promptSlackTokens: Int

        public static let `default` = RuntimeConfig(contextWindow: 4096, promptSlackTokens: 48)

        public init(contextWindow: UInt32, promptSlackTokens: Int) {
            self.contextWindow = contextWindow
            self.promptSlackTokens = promptSlackTokens
        }
    }

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var shouldCancel = false
    private let config: RuntimeConfig
    private var contextLimitTokens: Int = Int(RuntimeConfig.default.contextWindow)

    private var generationSampler: UnsafeMutablePointer<llama_sampler>?
    private var promptTokenBuffer: UnsafeMutablePointer<llama_token>?
    private var decSingleToken: UnsafeMutablePointer<llama_token>?

    private var nPos: Int = 0
    private var nPrompt: Int = 0
    private var nPredict: Int = 0
    private var lastSampledToken: llama_token = 0
    private var hasActiveGeneration: Bool = false

    private static let abortTrampoline: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { data in
        guard let data else { return false }
        let runtime = Unmanaged<LlamaCppRuntime>.fromOpaque(data).takeUnretainedValue()
        return runtime.shouldCancel
    }

    public init(config: RuntimeConfig = .default) {
        self.config = config
        self.contextLimitTokens = Int(config.contextWindow)
    }

    deinit {
        releaseGenerationState(freeContext: true)
        llama_backend_free()
    }

    public func loadModel(path: String) throws {
        releaseGenerationState(freeContext: true)
        shouldCancel = false

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            throw IntraiError.modelLoadFailed(reason: "Model file not found on disk.")
        }
        guard fileManager.isReadableFile(atPath: path) else {
            throw IntraiError.modelLoadFailed(reason: "Model file is not readable.")
        }
        let attributes = try fileManager.attributesOfItem(atPath: path)
        let size = attributes[.size] as? UInt64 ?? 0
        guard size > 0 else {
            throw IntraiError.modelLoadFailed(reason: "Model file is empty.")
        }

        llama_backend_init()

        var modelParams = llama_model_default_params()
#if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
#else
        modelParams.n_gpu_layers = -1
#endif

        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw IntraiError.modelLoadFailed(
                reason: "llama.cpp could not load the model file. The file may be corrupt or an unsupported format."
            )
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = config.contextWindow

        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        contextParams.n_threads = Int32(nThreads)
        contextParams.n_threads_batch = Int32(nThreads)

        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw IntraiError.modelLoadFailed(reason: "Unable to initialize llama context")
        }

        model = loadedModel
        context = loadedContext
        contextLimitTokens = Int(contextParams.n_ctx)
    }

    public func unloadModel() {
        releaseGenerationState(freeContext: true)
    }

    public func estimateTokenCount(for prompt: String) throws -> Int {
        guard let mdl = model else {
            throw IntraiError.modelNotLoaded
        }

        let vocab = llama_model_get_vocab(mdl)
        let estimated = prompt.withCString { cstr in
            Int(-llama_tokenize(vocab, cstr, Int32(strlen(cstr)), nil, 0, false, true))
        }
        guard estimated > 0 else {
            throw IntraiError.generationFailed(reason: "Failed to estimate prompt token count.")
        }
        return estimated
    }

    public func currentContextLimit() -> Int {
        contextLimitTokens
    }

    public func startGeneration(prompt: String, options: GenerationOptions) throws {
        guard let ctx = context, let mdl = model else {
            throw IntraiError.modelNotLoaded
        }
        shouldCancel = false
        releaseGenerationState(freeContext: false)

        if llama_model_has_encoder(mdl) {
            throw IntraiError.generationFailed(
                reason: "Encoder–decoder models are not supported yet. Use a text-only (decoder) GGUF model."
            )
        }

        let formatted = makeFormattedChatPrompt(userText: prompt, model: mdl)
        let vocab = llama_model_get_vocab(mdl)

        let nTok = formatted.withCString { cstr in
            Int32(-llama_tokenize(vocab, cstr, Int32(strlen(cstr)), nil, 0, false, true))
        }
        guard nTok > 0 else {
            throw IntraiError.generationFailed(reason: "Failed to tokenize the prompt (empty or invalid).")
        }
        let promptLimit = max(1, contextLimitTokens - config.promptSlackTokens)
        if Int(nTok) > promptLimit {
            throw IntraiError.contextLimitReached(
                reason: "The prompt is too long for the current context (\(contextLimitTokens) tokens)."
            )
        }

        let buf = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(nTok))
        let written = formatted.withCString { cstr in
            llama_tokenize(vocab, cstr, Int32(strlen(cstr)), buf, nTok, false, true)
        }
        guard written >= 0 else {
            buf.deallocate()
            throw IntraiError.generationFailed(reason: "Tokenization failed.")
        }

        let mem = llama_get_memory(ctx)
        llama_memory_clear(mem, true)

        decSingleToken = UnsafeMutablePointer<llama_token>.allocate(capacity: 1)

        var sp = llama_sampler_chain_default_params()
        sp.no_perf = true
        guard let smpl = llama_sampler_chain_init(sp) else {
            buf.deallocate()
            decSingleToken?.deallocate()
            decSingleToken = nil
            throw IntraiError.generationFailed(reason: "Failed to create sampler.")
        }
        let temp = max(0.0, min(2.0, options.temperature))
        if temp < 0.0001 {
            llama_sampler_chain_add(smpl, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.95, 1))
            llama_sampler_chain_add(smpl, llama_sampler_init_temp(Float(temp)))
            llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))
        }
        generationSampler = smpl

        let ctxLimit = contextLimitTokens
        let capNew = max(0, ctxLimit - Int(nTok) - 1)
        nPredict = min(max(0, options.maxTokens), capNew)
        nPrompt = Int(nTok)
        promptTokenBuffer = buf
        nPos = 0
        lastSampledToken = 0
        hasActiveGeneration = nPredict > 0

        if nPredict == 0 {
            releaseGenerationState(freeContext: false)
            throw IntraiError.contextLimitReached(
                reason: "No room left in context for a reply. Try a shorter message."
            )
        }

        llama_set_abort_callback(ctx, Self.abortTrampoline, Unmanaged.passUnretained(self).toOpaque())
    }

    public func nextTokenChunk() throws -> String? {
        guard let ctx = context, let mdl = model, let smpl = generationSampler, let pBuf = promptTokenBuffer, let sBuf = decSingleToken else {
            if model != nil, context != nil, !hasActiveGeneration { return nil }
            throw IntraiError.modelNotLoaded
        }
        if shouldCancel {
            releaseGenerationState(freeContext: false)
            return nil
        }
        guard hasActiveGeneration else { return nil }

        let vocab = llama_model_get_vocab(mdl)

        let batch: llama_batch
        if nPos == 0 {
            batch = llama_batch_get_one(pBuf, Int32(nPrompt))
        } else {
            sBuf.pointee = lastSampledToken
            batch = llama_batch_get_one(sBuf, 1)
        }

        let batchLen = Int(batch.n_tokens)
        if nPos + batchLen >= nPrompt + nPredict {
            releaseGenerationState(freeContext: false)
            return nil
        }

        let dret = llama_decode(ctx, batch)
        if dret < 0 {
            releaseGenerationState(freeContext: false)
            throw IntraiError.generationFailed(reason: "Inference error during decode (code \(dret)).")
        }
        if dret == 1 {
            releaseGenerationState(freeContext: false)
            throw IntraiError.contextLimitReached(reason: "Context full — try a shorter message.")
        }
        nPos += batchLen

        let newId = llama_sampler_sample(smpl, ctx, -1)
        if llama_vocab_is_eog(vocab, newId) {
            releaseGenerationState(freeContext: false)
            return nil
        }

        var piece = [CChar](repeating: 0, count: 512)
        var n = llama_token_to_piece(vocab, newId, &piece, Int32(piece.count), 0, true)
        if n < 0 {
            let need = -Int(n)
            piece = [CChar](repeating: 0, count: need + 1)
            n = llama_token_to_piece(vocab, newId, &piece, Int32(piece.count), 0, true)
        }
        lastSampledToken = newId

        guard n > 0 else { return "" }
        let clen = min(Int(n), piece.count)
        if clen < piece.count {
            piece[clen] = 0
        } else {
            piece[clen - 1] = 0
        }
        return String(cString: piece)
    }

    public func cancelGeneration() {
        shouldCancel = true
    }

    // MARK: - Internals

    private func makeFormattedChatPrompt(userText: String, model: OpaquePointer) -> String {
        guard let tmplPtr = llama_model_chat_template(model, nil) else {
            return Self.fallbackQwen25Chat(userText)
        }
        let template = String(cString: tmplPtr)
        if template.isEmpty {
            return Self.fallbackQwen25Chat(userText)
        }

        return "user".withCString { userRole in
            userText.withCString { userContent in
                var message = llama_chat_message(role: userRole, content: userContent)
                var out = [CChar](repeating: 0, count: 256_000)
                let written = withUnsafePointer(to: &message) { msgPtr in
                    template.withCString { tmplC in
                        Int(llama_chat_apply_template(
                            tmplC,
                            msgPtr,
                            1,
                            true,
                            &out,
                            Int32(out.count)
                        ))
                    }
                }
                if written < 0 || written >= out.count {
                    return Self.fallbackQwen25Chat(userText)
                }
                out[written] = 0
                guard let s = String(validatingUTF8: out) else {
                    return Self.fallbackQwen25Chat(userText)
                }
                if s.isEmpty { return Self.fallbackQwen25Chat(userText) }
                return s
            }
        }
    }

    private static func fallbackQwen25Chat(_ userText: String) -> String {
        // Last-resort ChatML: primary path uses `llama_model_chat_template` + `llama_chat_apply_template`.
        "<" + "|im_start|>user\n\(userText)<" + "|im_end|>\n<|im_start|>assistant\n"
    }

    private func releaseGenerationState(freeContext: Bool) {
        if let ctx = context {
            llama_set_abort_callback(ctx, nil, nil)
        }
        if let s = generationSampler {
            llama_sampler_free(s)
            generationSampler = nil
        }
        promptTokenBuffer?.deallocate()
        promptTokenBuffer = nil
        decSingleToken?.deallocate()
        decSingleToken = nil
        nPos = 0
        nPrompt = 0
        nPredict = 0
        lastSampledToken = 0
        hasActiveGeneration = false

        guard freeContext else { return }
        if let c = context {
            llama_free(c)
            context = nil
        }
        if let m = model {
            llama_model_free(m)
            model = nil
        }
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

    public func estimateTokenCount(for prompt: String) throws -> Int {
        _ = prompt
        throw IntraiError.modelNotLoaded
    }

    public func currentContextLimit() -> Int {
        0
    }

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
