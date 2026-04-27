# Intrai, with Llama.cpp

Intrai is a private, local-first multi-session chatbot for iOS, powered by an embedded
[llama.cpp](https://github.com/ggml-org/llama.cpp) runtime.

All conversations are stored on-device with SwiftData. MVP inference runs entirely on
the device with Apple Metal acceleration and no cloud inference dependency.

## MVP Scope (v1)

The v1 release is intentionally strict and focused on core chat reliability.

- **Multi-session chat**: Create, rename, and delete independent chat threads.
- **Persistent history**: Sessions and messages survive app relaunch.
- **Streaming responses**: Assistant output streams into the active message bubble.
- **Manual model import**: User imports a local `.gguf` file and loads it for inference.
- **Baseline error handling**: Friendly errors for model load failure, generation failure,
  and cancellation, with retry support for failed prompts.

### Explicitly Out of Scope for v1

- Memory snapshot system
- Markdown render/export features
- Context usage progress bar
- Siri / App Intents integration
- In-app model downloading UX
- Performance SLA enforcement (tokens/sec target)

## Requirements

- iOS 26.4+
- Xcode 26+
- Target hardware: iPhone 16 Pro and newer Pro-class iPhones
- Local clone of `llama.cpp` at `~/Local Documents/repos/llama.cpp`
- iOS-only `llama.xcframework` build path (simulator + device slices only)

## Architecture

### MVP Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Embed `llama.cpp` via XCFramework | Keeps all inference local and avoids local server-process complexity in v1. |
| Manual model import first | Lowest implementation and policy risk; avoids network and model-hosting UX complexity for MVP. |
| Local-first persistence with SwiftData | Matches product privacy goal and keeps session state robust across launches. |
| Functional stability as v1 acceptance gate | Prioritizes a reliable end-to-end experience before strict performance tuning. |

### Planned Phase Split

- **v1**: Core local chat + manual model import.
- **v1.1**: In-app model download workflow.
- **v1.2**: Performance baseline and throughput target enforcement.

## Building (MVP Workflow)

Intrai integrates a locally built **iOS-only** `llama.xcframework` from `llama.cpp`.
MVP intentionally excludes non-iOS framework slices to reduce build complexity and disk usage.

1. Build iOS-only XCFramework from local `llama.cpp` clone:
   - `chmod +x scripts/setup-llama-xcframework.sh`
   - `./scripts/setup-llama-xcframework.sh`
2. Add `vendor/llama/llama.xcframework` to the Intrai Xcode project.
3. Build Intrai for iOS simulator/device from Xcode.

## Documentation

- [Project Reference](docs/project-reference.md) - MVP requirements, technical design, and decisions
- [Architecture](docs/architecture.md) - module boundaries and protocol contracts
- [Data Models](docs/data-models.md) - SwiftData schema and persistence semantics
- [User Flows](docs/mvp-user-flows.md) - strict v1 UX flows and error behavior
- [Quality Gates](docs/quality-gates.md) - test checklist and instrumentation for MVP stability
- [Roadmap Phases](docs/phases-v1.1-v1.2.md) - scoped requirements for v1.1 and v1.2

## Source Layout

- Canonical app source root: `intrai-llamacpp/intrai-llamacpp/Intrai`

## License

MIT License

Copyright (c) 2026 by the Intrai/Intrai-Llama.cpp author(s)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
