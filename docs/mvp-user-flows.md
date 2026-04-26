# Intrai MVP User Flows

## 1) Session Management Flow

### Create Session

1. User taps "New Chat".
2. App creates `ChatSession` with default title (for example, "New Chat").
3. Empty thread view opens for that session.

### Rename Session

1. User invokes rename action from session list.
2. App validates non-empty title.
3. `ChatSession.title` updates and persists.

### Delete Session

1. User confirms delete action.
2. App deletes session.
3. Cascade removes all associated messages.
4. UI returns to remaining sessions or empty state.

## 2) Message Generation Flow (Streaming)

1. User enters prompt and submits.
2. App persists user message.
3. App creates assistant placeholder message with status `streaming`.
4. `InferenceEngine.generateStream` begins.
5. Chunks append to assistant message content in real time.
6. On completion, assistant status becomes `complete`.

## 3) Manual Model Import Flow (MVP)

1. User opens model settings/import action.
2. App presents file importer constrained to `.gguf`.
3. App validates selected file path and loadability.
4. `InferenceEngine.loadModel` is called.
5. UI surfaces loaded model status.

### Failure Cases

- Invalid extension -> reject and show model format guidance.
- Model load failure -> preserve previous model state and show clear error.
- Missing access/bookmark issue -> request re-selection.

## 4) Error and Recovery Flows

### Generation Failure

1. Streaming fails.
2. Assistant message status set to `failed` with reason.
3. UI offers one-tap retry using the same user prompt.

### Generation Cancellation

1. User taps cancel while streaming.
2. Inference cancellation is requested.
3. Assistant message status set to `cancelled`.

### Model Not Loaded

1. User attempts to send prompt without active model.
2. App blocks generation and prompts user to import/load a model.

## UX Rules for MVP

- Preserve transcript integrity over aggressive cleanup.
- Prefer explicit user actions for destructive operations.
- Keep all user-visible errors actionable and local-first.
