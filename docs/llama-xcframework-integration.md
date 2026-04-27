# llama.cpp XCFramework Integration

This document tracks the embedded `llama.cpp` integration path for Intrai MVP.
MVP is explicitly iOS-only: iPhone 16 Pro+ on iOS 26.4+.

## 1) Build and copy the XCFramework (iOS-only)

From this repo root:

```bash
chmod +x scripts/setup-llama-xcframework.sh
./scripts/setup-llama-xcframework.sh
```

The script expects:

- local clone at `~/Local Documents/repos/llama.cpp`
- output copied into `vendor/llama/llama.xcframework`
- slices built only for:
  - `iphoneos` (device)
  - `iphonesimulator` (simulator)

## 2) Framework reference in Xcode project

The framework is already wired into the Xcode project file:

- `PBXFileReference` pointing to `../vendor/llama/llama.xcframework`
- `PBXBuildFile` in the app target's Frameworks build phase
- `OTHER_LDFLAGS = -lc++` for C++ standard library linkage
- Module import resolves as `import llama`

No manual drag-and-drop is needed after running the build script.

## 3) Runtime bridge and inference engine seams

Step 3 adds these concrete integration scaffolds:

- `intrai-llamacpp/intrai-llamacpp/Intrai/Inference/LlamaCppRuntime.swift`
  - `LlamaCppBridge` implementation
  - model load/unload behavior
  - compile-safe fallback when `llama` module is not linked yet
- `intrai-llamacpp/intrai-llamacpp/Intrai/Inference/LlamaCppInferenceEngine.swift`
  - `InferenceEngine` implementation
  - async stream surface with cancellation plumbing

## 4) Current limitations

- Tokenization/sampling decode loop in `LlamaCppRuntime` is placeholder.
  `startGeneration` and `nextTokenChunk` accept inputs but return `nil` immediately.
  Wiring the real llama.cpp token decode loop is the next implementation step.
- Framework linking and `import llama` module resolution are verified (build succeeds
  with zero errors and zero warnings).

## 5) Scope guardrail

- Do not use the upstream all-platform `llama.cpp/build-xcframework.sh` workflow for Intrai MVP.
- Intrai's setup script intentionally builds iOS-only slices to avoid unnecessary platform artifacts and excessive build/disk overhead.

## 6) Real-device tuning guidance (reference)

These settings are recommended starting points for iPhone 16 Pro+ runtime tuning once
the real token decode loop is wired in `LlamaCppRuntime`.

- `n_gpu_layers`:
  - Real device: set to `-1` (or a value >= model layer count) to maximize Metal offload.
  - Simulator: keep `0` (CPU-only) for correctness and predictable behavior.
- `n_ctx`:
  - Start at `4096` (or `2048` if prompts are short and memory headroom is tight).
  - Move to `8192` only when needed for product UX; avoid very large defaults.

Notes:

- Higher `n_ctx` increases KV cache memory usage significantly.
- Full GPU offload can still fail if the chosen model/quantization exceeds device memory.
- Current runtime still uses placeholder generation, so these values should be treated as
  policy defaults to validate after token generation is fully implemented.

## 7) Real-device tuning checklist (runbook)

Use this once token generation is fully implemented in `LlamaCppRuntime`.

### Test preconditions

- Device: iPhone 16 Pro or newer Pro model on iOS 26.4+.
- Build: Release configuration.
- Model: one fixed `.gguf` model/quantization for all runs.
- Prompt fixture:
  - short prompt (~32-64 tokens)
  - medium prompt (~256-512 tokens)
  - long prompt (~1024+ tokens)
- Generation fixture:
  - fixed `temperature`
  - fixed `maxTokens`
  - run each case 3 times and record median.

### Parameter matrix

Run these combinations in order:

1. `n_gpu_layers = 0`, `n_ctx = 2048` (CPU baseline, sanity check)
2. `n_gpu_layers = -1`, `n_ctx = 2048`
3. `n_gpu_layers = -1`, `n_ctx = 4096` (recommended default candidate)
4. `n_gpu_layers = -1`, `n_ctx = 8192` (only if product UX needs more context)

If `-1` is unsupported in your linked llama.cpp revision, use a large value
(>= model layer count) for full offload.

### Metrics to capture per run

- `timeToFirstTokenMs`
- `generationDurationMs`
- `streamedCharacterCount`
- `wasCancelled`
- `generationFailed`
- app memory pressure/crash behavior (manual observation)

### Pass/fail criteria

For each matrix row:

- Pass if:
  - no crash/OOM
  - no generation failure for normal prompts
  - cancellation still works and sets `wasCancelled = true`
  - retry path still succeeds after forced failure case
- Fail if:
  - app terminates, model unloads unexpectedly, or repeated failures appear
  - TTFT or duration regresses badly vs previous stable row without added UX value

### Selection rule for shipping defaults

- Pick the smallest `n_ctx` that satisfies real prompt-length needs.
- Prefer full GPU offload (`n_gpu_layers = -1` or equivalent) when stable.
- Initial default target:
  - real device: `n_gpu_layers = -1`, `n_ctx = 4096`
  - simulator: `n_gpu_layers = 0`
- Promote to `n_ctx = 8192` only after verified need and stable memory behavior.
