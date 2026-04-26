# Intrai Follow-On Phases

## v1.1 - In-App Model Download

## Objective

Add a guided in-app model acquisition flow while preserving local-first inference.

## Requirements

- Curated model catalog (name, size, quantization, source URL).
- User-initiated download actions only.
- Download progress, cancel, and retry behavior.
- Local file persistence in app-managed storage.
- Model integrity checks before load.
- Disk management UX (list/remove downloaded models).

## Network Policy

- Network access is limited to explicit model download operations.
- No background analytics or generic telemetry uploads.

## Acceptance

- User can download, load, and remove a curated model end-to-end.
- Interrupted download can be retried without app restart.

---

## v1.2 - Performance Baseline and Enforcement

## Objective

Define measurable generation performance targets for recommended models on target hardware.

## Requirements

- Benchmark harness for repeated generation runs.
- Standardized prompt fixture and deterministic test settings.
- Throughput metric capture (tokens/sec) and latency stats.
- Recommended default generation parameters for target devices.

## Suggested Gate (To Finalize)

- Minimum tokens/sec threshold on iPhone 16 Pro+ for one recommended model quantization.
- Maximum allowable time-to-first-token under benchmark fixture conditions.

## Acceptance

- Baseline target values documented and reproducible.
- CI/manual benchmark process can detect regressions.
