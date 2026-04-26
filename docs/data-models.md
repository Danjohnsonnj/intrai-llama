# Intrai MVP Data Models

## SwiftData Entity Definitions (Planned)

## `ChatSession`

- `id: UUID`
- `title: String`
- `createdAt: Date`
- `updatedAt: Date`
- `messages: [ChatMessage]`

### Semantics

- `title` can be user-defined. For v1, no automatic title generation is required.
- `updatedAt` is refreshed when a new message is added to the session.
- Sessions are ordered by `updatedAt` descending in the sidebar.

## `ChatMessage`

- `id: UUID`
- `session: ChatSession` (inverse relation)
- `role: MessageRole` (`user` or `assistant`)
- `content: String`
- `status: MessageStatus` (`pending`, `streaming`, `complete`, `failed`, `cancelled`)
- `createdAt: Date`
- `errorReason: String?`

### Semantics

- User message is persisted first, then assistant placeholder.
- Assistant content is appended incrementally as stream chunks arrive.
- Final status transitions:
  - `streaming -> complete`
  - `streaming -> failed`
  - `streaming -> cancelled`

## Deletion and Cascades

- Deleting a `ChatSession` must cascade-delete all related `ChatMessage` records.
- There should never be orphan messages without a session relationship.

## Ordering Rules

- `ChatSession` list: newest activity first via `updatedAt DESC`.
- `ChatMessage` list: chronological order via `createdAt ASC`.

## Persistence Behavior for Failures

- If generation fails, the assistant message remains in transcript with `failed` status.
- Retry operation reuses original user message content and creates a new assistant message.
- Failed/cancelled generations do not delete user prompts.

## Migration Expectations

- v1 schema is intentionally minimal.
- Future migration candidates:
  - `tokenCount` fields
  - model metadata per session
  - snapshot metadata for memory system
