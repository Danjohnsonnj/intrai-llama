# Intrai — Project Reference

## Overview

Intrai is a local-first iOS chatbot that embeds `llama.cpp` through an XCFramework.
The MVP is scoped to reliable core chat behavior on iPhone 16 Pro+ devices running iOS 26.4+.

---

## Current Status

Discovery complete for MVP boundaries. Entering implementation with explicit phase splits.

---

## Functional Capabilities

### In Scope for MVP (v1)

- Multi-session chat creation, rename, and deletion.
- Persistent conversation history using SwiftData.
- Assistant response streaming for active chat thread.
- Manual `.gguf` model import and local model loading.
- Error and recovery flows for model load failure, generation failure, and cancellation.

### Out of Scope for MVP (Deferred)

- Memory snapshot system.
- Markdown render/export enhancements.
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

### Source Files (Planned)

- `docs/architecture.md`
- `docs/data-models.md`
- `docs/mvp-user-flows.md`
- `docs/quality-gates.md`
- `docs/phases-v1.1-v1.2.md`

### Data Models

- `ChatSession`: id, title, createdAt, updatedAt
- `ChatMessage`: id, sessionId relation, role, content, status, createdAt
- Cascade delete: removing a session removes all related messages.

### AI Service Design (MVP)

- Embedded `llama.cpp` loaded through `llama.xcframework`.
- No local server boundary in v1.
- Model selected via manual `.gguf` import.
- Streaming generation loop emits chunks to the UI.

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

## Known Pending Items

- Define and ship in-app download flow in v1.1.
- Establish measurable performance targets in v1.2.
- Expand device support matrix after v1 stability validation.
