# Intrai MVP Quality Gates

## Release Goal

v1 is accepted when core local chat flows are stable and recoverable on target devices.
Strict throughput SLAs are deferred to v1.2.

## Smoke Checklist (MVP)

- [x] App launches cleanly with empty and populated data stores.
- [ ] Session create/rename/delete persists across relaunch.
- [ ] Session delete cascades message removal.
- [ ] Manual `.gguf` import succeeds for at least one supported model.
- [ ] Imported model reload remains stable after app restart.
- [ ] Prompt submission streams assistant content to UI.
- [ ] Cancellation interrupts stream without app instability.
- [ ] Generation failure marks message state and exposes retry.
- [ ] Retry successfully produces a new assistant response record.

Detailed execution checklist: [`docs/mvp-smoke-checklist.md`](mvp-smoke-checklist.md)

## Device/Test Matrix (Initial)

- [x] iPhone 16 Pro on iOS 26.4+
- [x] iOS simulator for non-inference UI checks

## Instrumentation (Non-SLA in v1)

Collect for diagnostics only:

- [ ] `timeToFirstTokenMs`
- [ ] `generationDurationMs`
- [ ] `streamedCharacterCount`
- [ ] `inputTokenEstimate`
- [ ] `contextUtilization`
- [ ] `compactionApplied`
- [ ] `generationPath` (`cold`, `warm`)
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
- [ ] `endReason` (`completed`, `cancelled`, `failed`, `contextLimited`)

Metrics should be local development diagnostics, not telemetry uploads in v1.

### Current implementation hooks

- `ChatViewModel.lastGenerationMetrics`
- `ChatViewModel.recentGenerationMetrics`
- `MetricsRecorder` protocol for pluggable sinks
- `ConsoleMetricsRecorder` default local logging sink
- `InMemoryMetricsRecorder` for test/dev assertions

## Exit Criteria for MVP

- All smoke checklist items pass on at least one physical target device.
- No critical crashers in model import, generation, or session persistence flows.
- Known issues are documented with severity and workaround.

## v1.2 Benchmark Protocol (Manual Baseline)

- Reference profile: iPhone 16 Pro+, iOS 26.4+, Low Power Mode off, no active thermal warning.
- Model fixture: fixed model filename and quantization per run sheet.
- Prompt fixture: short, medium, and long prompts held constant across runs.
- Run policy: 5 runs per prompt length; record cold separately from warm.
- Warm baseline policy: classify warm-only from run 2 onward if run 1 is cold.

### Reporting template

| Prompt class | Run class | TTFT p50 (ms) | TTFT p90 (ms) | Sustained chars/sec | Notes |
| --- | --- | --- | --- | --- | --- |
| short | cold |  |  |  |  |
| short | warm |  |  |  |  |
| medium | cold |  |  |  |  |
| medium | warm |  |  |  |  |
| long | cold |  |  |  |  |
| long | warm |  |  |  |  |
