# llama.cpp XCFramework Integration (Step 3)

This document tracks the embedded `llama.cpp` integration path for Intrai MVP.

## 1) Build and copy the XCFramework

From this repo root:

```bash
chmod +x scripts/setup-llama-xcframework.sh
./scripts/setup-llama-xcframework.sh
```

The script expects:

- local clone at `~/Local Documents/repos/llama.cpp`
- output copied into `vendor/llama/llama.xcframework`

## 2) Add framework to Xcode project

Once the Intrai Xcode project exists:

1. Drag `vendor/llama/llama.xcframework` into project navigator.
2. Add it to target `Frameworks, Libraries, and Embedded Content`.
3. Ensure module import resolves as `import llama`.

## 3) Runtime bridge and inference engine seams

Step 3 adds these concrete integration scaffolds:

- `Intrai/Inference/LlamaCppRuntime.swift`
  - `LlamaCppBridge` implementation
  - model load/unload behavior
  - compile-safe fallback when `llama` module is not linked yet
- `Intrai/Inference/LlamaCppInferenceEngine.swift`
  - `InferenceEngine` implementation
  - async stream surface with cancellation plumbing

## 4) Current limitations

- Tokenization/sampling decode loop is intentionally placeholder in this step.
- Full per-token generation logic is completed in a later implementation step.
- Framework linking cannot be fully validated until project/target wiring exists.
