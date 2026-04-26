# Intrai App Skeleton

This directory defines the initial app module boundaries for MVP implementation.

## Structure

- `App`
  - Application entry, root navigation, dependency wiring.
- `Features/Chat`
  - Chat-facing view models and feature composition.
- `Data`
  - Persistence contracts and storage-facing repository protocols.
- `Inference`
  - Inference contracts and bridge seam for `llama.cpp` runtime integration.
- `Shared`
  - Cross-module domain types and shared error definitions.

## Boundary Rule

Feature code depends on repository/inference protocols, not concrete implementations.
Concrete implementations are introduced in later steps.
