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
- [ ] Long resumed chats with recap prompts (for example, `Summarize this chat`, `Where were we?`) compact history and stay stable
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
  - [ ] `generationPath`
  - [ ] `preflightDurationMs`
  - [ ] `promptAssemblyDurationMs`
  - [ ] `tokenEvaluationDurationMs`
  - [ ] `engineQueueDurationMs`
  - [ ] `decodeToFirstChunkMs`
  - [ ] `forcedRecapCompactionApplied`
  - [ ] `recapIntentMatched`
  - [ ] `preflightHistoryTruncatedForSafety`
  - [ ] `wasCancelled`
  - [ ] `generationFailed`
  - [ ] `endReason`

## Performance Baseline Runbook (v1.2 prep)

- [ ] Capture device conditions (device model, iOS version, Low Power Mode, thermal state).
- [ ] Use fixed prompt fixture: short / medium / long.
- [ ] Run 5 generations per prompt class and tag each as `cold` or `warm`.
- [ ] Record TTFT p50/p90 and sustained chars/sec for warm runs.
- [ ] Confirm one repeated run produces comparable values (no large unexplained drift).

## Exit Criteria

- [ ] No critical crashes in session CRUD, model load, generation, cancel, or retry
- [ ] Any known issues recorded with severity and workaround
