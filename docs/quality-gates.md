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
