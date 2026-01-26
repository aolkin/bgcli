# Move polling and long-running ops off MainActor

Summary

`SessionManager.startPolling()` creates a `Task { @MainActor ... }` that loops and calls `refreshAllStatuses()`. Even if the status-checking functions are nonisolated, scheduling the polling loop on the MainActor risks UI jank and makes the app less responsive under heavy IO.

Goal

Run polling and other long-running I/O on a background actor / detached task and confine only UI updates to the MainActor.

Proposed Work

- Move the polling loop off the MainActor (use `Task.detached` or a dedicated background actor) so `listSessions` and network/ssh operations run off the main thread.
- Ensure only minimal state mutations (writes to `@Published sessionStates`) happen on MainActor via `MainActor.run` calls.
- Add exponential backoff for repeated failures and allow pausing/resuming polling (e.g., when Settings window is open or app inactive).
- Add instrumentation and tests that demonstrate main-thread responsiveness during heavy polling.

Tasks

- [ ] Refactor `startPolling()` to create a non-@MainActor polling task (or a background actor wrapper).
- [ ] Update `refreshAllStatuses()` / `refreshHostStatuses()` to do work off-main and dispatch UI updates back to MainActor.
- [ ] Implement per-host failure tracking and exponential backoff.
- [ ] Add tests / manual smoke test to confirm no main-thread blocking.

Acceptance Criteria

- Polling loop no longer executes work on MainActor.
- UI remains responsive under simulated heavy session listing.
- Polling supports pause/resume and backoff logic on repeated failures.

Relevant files

- bgcli/Services/SessionManager.swift

Estimated effort: 1 day
