# Intrai MVP Quality Gates

## Release Goal

v1 is accepted when core local chat flows are stable and recoverable on target devices.
Strict throughput SLAs are deferred to v1.2.

## Smoke Checklist (MVP)

- App launches cleanly with empty and populated data stores.
- Session create/rename/delete persists across relaunch.
- Session delete cascades message removal.
- Manual `.gguf` import succeeds for at least one supported model.
- Imported model reload remains stable after app restart.
- Prompt submission streams assistant content to UI.
- Cancellation interrupts stream without app instability.
- Generation failure marks message state and exposes retry.
- Retry successfully produces a new assistant response record.

Detailed execution checklist: [`docs/mvp-smoke-checklist.md`](mvp-smoke-checklist.md)

## Device/Test Matrix (Initial)

- iPhone 16 Pro on iOS 26.4+
- iPhone 16 Pro Max on iOS 26.4+ (recommended secondary check)
- iOS simulator for non-inference UI checks

## Instrumentation (Non-SLA in v1)

Collect for diagnostics only:

- `timeToFirstTokenMs`
- `generationDurationMs`
- `streamedCharacterCount`
- `wasCancelled`
- `generationFailed`

Metrics should be local development diagnostics, not telemetry uploads in v1.

### Current implementation hooks

- `ChatViewModel.lastGenerationMetrics`
- `MetricsRecorder` protocol for pluggable sinks
- `ConsoleMetricsRecorder` default local logging sink
- `InMemoryMetricsRecorder` for test/dev assertions

## Exit Criteria for MVP

- All smoke checklist items pass on at least one physical target device.
- No critical crashers in model import, generation, or session persistence flows.
- Known issues are documented with severity and workaround.
