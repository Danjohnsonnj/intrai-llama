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
2. App runs prompt preflight:
   - assembles candidate prompt from summary + recent history + user input
   - estimates input tokens and evaluates context budget pressure
   - applies soft compaction to older history only when required
   - for recap-style prompts on very large resumed chats, applies deterministic forced
     compaction using bounded summary + recent tail turns before token estimation
3. App surfaces context notice/details when pressure or compaction applies.
4. App persists user message.
5. App creates assistant placeholder message with status `streaming`.
6. `InferenceEngine.generateStream` begins.
7. Chunks append to assistant message content in real time.
8. On completion, assistant status becomes `complete`.

### Monitoring Surface During Generation

- Header-adjacent monitoring strip shows:
  - context state labels: `Context healthy`, `Context near limit`, `Compaction active`, `Context blocked`
  - generation health labels: `Generation healthy`, `Generation slow`, `Compacted response`, `Generation cancelled`, `Generation failed`, `Context limited`
  - live streaming activity with approximate throughput.
- Context details panel can expand to show budget utilization and latest generation outcome.
- Context notice copy uses:
  - `Context near limit`
  - `Context high`
  - `Context full`
  - `History compacted to preserve response quality`
  - `History compacted for recap stability`

### Recap Request Stability Path

1. User submits recap-style request (for example, `Summarize this chat`,
   `What were we talking about?`, `Where were we?`, `Catch me up`) in a long resumed thread.
2. Preflight detects recap intent and/or oversized history and switches to recap safety mode.
3. App composes a bounded recap prompt from:
   - persisted rolling summary (clamped)
   - recent verbatim tail turns
   - user recap request
4. Older history outside the bounded window is intentionally omitted for stability.
5. If the bounded recap prompt still exceeds safe limits, app stops with actionable context guidance
   instead of looping or freezing.

## 3) Manual Model Import Flow (MVP)

1. User taps "Load Model".
2. App presents a file importer constrained to `.gguf`.
3. App starts security-scoped access to the picked URL, validates the file (exists,
   readable, non-zero size), and copies it into app-managed storage under
   Application Support/Models/ (same filename; replaces prior copy of that name).
4. `InferenceEngine.loadModel` is called with the app-local file URL.
5. UI surfaces loaded model status.

Re-importing the same filename refreshes the stored copy. Inference always reads the
stabilized path so loading does not depend on the Files provider session after the
picker dismisses.
On app relaunch, the most recently loaded model is restored automatically when that
stored file is still available in app-managed storage.

### Failure Cases

- Invalid extension -> reject and show model format guidance.
- Unreadable or empty file -> show a specific error; suggest moving the file to On
  My iPhone and retrying.
- Copy or storage failure -> show error; previous model state remains unless load succeeds.
- llama.cpp load failure (unsupported or corrupt GGUF) -> show error with guidance.

## 4) Error and Recovery Flows

### Generation Failure

1. Streaming fails.
2. Assistant message status set to `failed` with reason.
3. UI offers one-tap retry using the same user prompt.

### Context Limit Reached

1. Prompt preflight or decode path detects context budget exhaustion.
2. App surfaces user-facing guidance ('Context full. Start a new chat or shorten your message.').
3. Monitoring state transitions to `Context blocked` / `Context limited` for visibility.

### Generation Cancellation

1. User taps cancel while streaming.
2. Inference cancellation is requested.
3. Assistant message status set to `cancelled`.

### Model Not Loaded

1. User attempts to send prompt without active model.
2. App blocks generation and prompts user to import/load a model.

## 5) Markdown Rendering and Export Flow

1. Message bubbles render markdown content for both user and assistant messages.
2. Rendering uses `MarkdownUI` to preserve multiline content and block elements
   (including tables) with consistent output.
3. User can trigger "Copy chat as Markdown" from the chat header action.
4. App copies the current chat transcript to clipboard as plain text formatted markdown.
5. Copy action is unavailable when no transcript content exists.

## UX Rules for MVP

- Preserve transcript integrity over aggressive cleanup.
- Prefer explicit user actions for destructive operations.
- Keep all user-visible errors actionable and local-first.
