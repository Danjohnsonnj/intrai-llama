# Intrai — Project Reference

## Overview

Intrai is a local-first iOS chatbot that embeds `llama.cpp` through an XCFramework.
The MVP is scoped to reliable core chat behavior on iPhone 16 Pro+ devices running iOS 26.4+.

---

## Current Status

Core implementation complete. Xcode project builds with zero errors and zero warnings.
`LlamaCppRuntime` now performs real llama.cpp tokenization/sampling for streaming output.
Context-budget preflight, soft compaction, and monitoring UI states are implemented.
Manual smoke testing on device is pending.

---

## Functional Capabilities

### In Scope for MVP (v1)

- Multi-session chat creation, rename, and deletion.
- Persistent conversation history using SwiftData.
- Session list recency timestamps use simplified buckets (`moments ago`, rounded minutes,
  rounded hours, whole days).
- Chats titled `New Chat` can be auto-renamed once after the first successful turn with a
  local 5-word summary prefixed by `✦ `; manual user renames are never overridden.
- Assistant response streaming for active chat thread.
- Manual `.gguf` model import and local model loading.
- Markdown rendering in chat messages and markdown-formatted clipboard export.
- Error and recovery flows for model load failure, generation failure, and cancellation.
- **Global system prompt and user memory** (v1): editable in app settings, stored in
  `UserDefaults`, with character limits. Injected on every send after the system line and
  before summary/history. Empty/whitespace system prompt uses the built-in default line;
  empty user memory omits the user memory block. Edits apply on the next user message in
  any chat.

### Out of Scope for MVP (Deferred)

- Memory snapshot system.
- Rich markdown render/export enhancements beyond in-chat rendering and clipboard copy.
- Context usage progress bar.
- Siri/App Intents integration.
- In-app model downloading UX.
- Performance SLA thresholds.

---

## Technical Design

### Architecture Pattern

- Layered modular app architecture:
  - `App` for entry and navigation
  - `Features/Chat` for UI and state coordination
  - `Inference` for llama runtime wrapper and token streaming
  - `Data` for SwiftData entities and repositories
  - `Shared` for cross-cutting models/errors

### Source Files

- Xcode project: `intrai-llamacpp/intrai-llamacpp.xcodeproj`
- Canonical app source root: `intrai-llamacpp/intrai-llamacpp/Intrai`
- Documentation: `docs/architecture.md`, `docs/data-models.md`, `docs/mvp-user-flows.md`,
  `docs/quality-gates.md`, `docs/phases-v1.1-v1.2.md`, `docs/llama-xcframework-integration.md`

### Data Models

- `ChatSession`: id, title, createdAt, updatedAt
- `ChatMessage`: id, sessionId relation, role, content, status, createdAt
- Cascade delete: removing a session removes all related messages.

### AI Service Design (MVP)

- Embedded `llama.cpp` loaded through `llama.xcframework`.
- XCFramework build path is iOS-only for MVP (iphoneos + iphonesimulator slices).
- No local server boundary in v1.
- Model selected via manual `.gguf` import; files are copied into Application Support/Models
  after a security-scoped read so loads succeed after the document picker closes.
- Resume closed app (force quit or system closed) with previously selected model, if it is still accessible.
- Model name should be present on the main screen.
- Streaming generation loop emits chunks to the UI.
- Prompt preflight estimates token usage against current context window and applies
  soft history compaction only when needed.
- Recap-style prompts (for example, 'Summarize this chat', 'Where were we?') on large
  resumed threads can trigger deterministic forced compaction to preserve stability:
  - bounded summary + recent tail messages are used instead of broad full-history assembly
  - history truncation is explicit and tracked for diagnostics
  - fail-fast context guidance is shown if recap prompt still exceeds safe limits
- Chat thread surfaces monitoring states with user-facing labels:
  - Context: `Context healthy`, `Context near limit`, `Compaction active`, `Context blocked`
  - Generation: `Generation healthy`, `Generation slow`, `Compacted response`,
    `Generation cancelled`, `Generation failed`, `Context limited`
- Context detail UI can show budget utilization and latest generation diagnostics.
- Local diagnostics include recap-safety telemetry:
  - `forcedRecapCompactionApplied`
  - `recapIntentMatched`
  - `preflightHistoryTruncatedForSafety`
- Chat message markdown rendering uses `MarkdownUI` to correctly handle multiline content
  and table blocks in message bubbles.
- Header model status uses concise labels (for example, 'Model ready', 'Loading model',
  'Restoring model', 'No model loaded') without showing the active model filename.

### Context Assembly Pipeline

- v1 pipeline: Session messages (ordered) -> prompt assembly -> inference stream -> persisted assistant message updates.
- Memory snapshot and advanced context policies are deferred.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Embedded XCFramework instead of local server | Reduces moving parts and keeps inference local in-process for MVP. |
| Manual model import first | Minimizes legal/distribution/network complexity in first release. |
| Functional reliability before performance SLA | Ensures stable UX before setting strict throughput requirements. |
| Pro-device baseline (iPhone 16 Pro+) | Narrows hardware variability during first implementation cycle. |

---

## Out of Scope (MVP Exclusions)

- In-app model download experience
- Token-throughput SLA and benchmark gate
- Siri integration and App Intents
- Context usage progress visualization
- Memory snapshot freeze/refresh workflow
- Rich markdown rendering/export pipeline

## Future Product Requirements and Improvements

- [ ] Structured or searchable user memory; optional iCloud or export for prompt settings.
- [ ] Per-session system prompt override or optional snapshot of prompt per chat (v1 is global only; next message always uses current global text).

## Known Pending Items

- Apply and validate real-device runtime defaults (`n_gpu_layers` for full Metal offload,
  `n_ctx` baseline 4096/8192 policy) during on-device tuning pass.
- Run full MVP smoke checklist on physical device.
- Define and ship in-app download flow in v1.1.
- Add AirDrop-based `.gguf` transfer workflow (no iCloud requirement) as part of
  model acquisition UX.
- Establish measurable performance targets in v1.2.
- ~Expand device support matrix after v1 stability validation.~
