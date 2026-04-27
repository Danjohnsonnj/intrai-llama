# Intrai MVP Smoke Checklist (Execution)

Use this checklist during manual validation runs.

## Setup

- [ ] Device: iPhone 16 Pro or newer Pro model on iOS 26.4+
- [ ] Build uses local embedded `llama.xcframework`
- [ ] Test `.gguf` model file available for import

## Core Chat Reliability

- [ ] Launch app with empty data store succeeds
- [ ] Create session succeeds and appears in list
- [ ] Rename session persists after relaunch
- [ ] Delete session removes thread and related messages
- [ ] Existing sessions/messages load correctly after relaunch

## Inference and Streaming

- [ ] Manual `.gguf` import succeeds (file copied under Application Support/Models; not dependent on Files session after dismiss)
- [ ] Re-importing the same `.gguf` filename refreshes the stored copy and loads
- [ ] Sending prompt creates user + assistant placeholder entries
- [ ] Assistant message streams incrementally
- [ ] Cancel generation marks assistant message as `cancelled`
- [ ] Generation failure marks assistant message as `failed`
- [ ] Retry from failed prompt produces a new assistant response

## Local Instrumentation Check

- [ ] `lastGenerationMetrics` updates after a generation attempt
- [ ] Recorded metrics include:
  - [ ] `timeToFirstTokenMs`
  - [ ] `generationDurationMs`
  - [ ] `streamedCharacterCount`
  - [ ] `wasCancelled`
  - [ ] `generationFailed`

## Exit Criteria

- [ ] No critical crashes in session CRUD, model load, generation, cancel, or retry
- [ ] Any known issues recorded with severity and workaround
