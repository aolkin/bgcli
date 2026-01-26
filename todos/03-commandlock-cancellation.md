# Make CommandLock cancellation-aware and avoid leaked continuations

Summary

`SessionManager.CommandLock` keeps an array of `CheckedContinuation<Void, Never>` waiters appended via `withCheckedContinuation`, but there is no handling for task cancellation; cancelled waiters can leave stale continuations in the queue and lead to deadlocks or memory growth.

Goal

Make the lock cancellation-aware so that when a waiting task is cancelled its continuation is removed and resources are released. Prefer a well-tested primitive (e.g., AsyncSemaphore) or implement explicit cancellation handlers.

Proposed Work

- Replace the current continuation-based queue with a cancellation-aware implementation:
  - Option A: Use an AsyncSemaphore-like construct that supports Task cancellation out of the box.
  - Option B: Store waiters as objects that include the Task handle and register cancellation handlers that remove the waiter.
- Ensure `withCommandLock(...)` correctly manages `inFlightOperations` and `operationGenerations` in all exit paths, including cancellation.
- Add unit tests that cancel waiting tasks and assert the lock remains functional and waiters are cleaned up.

Tasks

- [ ] Research and pick a safe implementation pattern (AsyncSemaphore or cancellable continuations).
- [ ] Implement a cancellation-aware CommandLock in `SessionManager`.
- [ ] Add tests simulating cancellations and concurrency.
- [ ] Validate that `withCommandLock` does not leak state when operations error or are cancelled.

Acceptance Criteria

- Cancelled waiting tasks are removed from the waiter queue.
- No deadlocks or leaked waiters after repeated cancellations in tests.

Relevant files

- bgcli/Services/SessionManager.swift

Estimated effort: 1 day
