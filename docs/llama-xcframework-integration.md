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
