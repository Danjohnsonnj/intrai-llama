# Intrai MVP Smoke Checklist (Execution)

Use this checklist during manual validation runs.

## Setup

- [x] Device: iPhone 16 Pro or newer Pro model on iOS 26.4+
- [x] Build uses local embedded `llama.xcframework`
- [x] Test `.gguf` model file available for import

## Core Chat Reliability

- [x] Launch app with empty data store succeeds
- [x] Create session succeeds and appears in list
- [x] Rename session persists after relaunch
- [x] Delete session removes thread and related messages
- [x] Existing sessions/messages load correctly after relaunch

## Inference and Streaming

- [x] Manual `.gguf` import succeeds (file copied under Application Support/Models; not dependent on Files session after dismiss)
- [ ] Re-importing the same `.gguf` filename refreshes the stored copy and loads
- [x] Sending prompt creates user + assistant placeholder entries
- [ ] Context preflight shows `Context near limit` or `History compacted to preserve response quality` when applicable
- [x] Assistant message streams incrementally
- [ ] Cancel generation marks assistant message as `cancelled`
- [ ] Generation failure marks assistant message as `failed`
- [ ] Context-limit stop shows actionable guidance plus `Context blocked` / `Context limited` states
- [ ] Retry from failed prompt produces a new assistant response

## Local Instrumentation Check

- [ ] `lastGenerationMetrics` updates after a generation attempt
- [ ] Recorded metrics include:
  - [ ] `timeToFirstTokenMs`
  - [ ] `generationDurationMs`
  - [ ] `streamedCharacterCount`
  - [ ] `inputTokenEstimate`
  - [ ] `contextUtilization`
  - [ ] `compactionApplied`
  - [ ] `wasCancelled`
  - [ ] `generationFailed`
  - [ ] `endReason`

## Exit Criteria

- [ ] No critical crashes in session CRUD, model load, generation, cancel, or retry
- [ ] Any known issues recorded with severity and workaround
