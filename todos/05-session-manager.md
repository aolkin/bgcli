# 05: Session Manager

## Objective
Create the central orchestration service that manages session lifecycle, polls for status updates, and handles auto-restart logic.

## Prerequisites
- 01-project-setup complete
- 02-models complete
- 03-shell-utility complete
- 04-tmux-service complete

## Deliverables
1. `SessionManager` as the main ObservableObject
2. Polling mechanism for session status
3. Auto-restart logic with failure tracking
4. macOS notification integration for failures

## Files to Create
- `bgcli/Services/SessionManager.swift`

---

## SessionManager

### Purpose
The "brain" of the application. Maintains the source of truth for all session states, coordinates with TmuxService, and publishes changes for the UI.

### Design
- `@MainActor` class conforming to `ObservableObject`
- Singleton or injected via environment
- Owns the polling timer
- Publishes state changes for SwiftUI

### Published Properties
| Property | Type | Description |
|----------|------|-------------|
| `commands` | `[Command]` | Loaded from config |
| `sessionStates` | `[String: SessionState]` | Keyed by command ID |
| `isLoading` | `Bool` | True during initial load |
| `lastError` | `String?` | Most recent error message |

### Dependencies
- `TmuxService` - for tmux operations
- `AppConfig` - for loading/saving configuration
- `UserNotificationCenter` - for failure notifications

---

## Initialization Flow

1. Load `AppConfig` from disk
2. Populate `commands` array
3. Initialize `sessionStates` with default `SessionState` for each command
4. Start polling timer
5. Perform initial status refresh

---

## Core Methods

### Configuration Management
```
func loadConfig() async throws
func reloadConfig() async throws  // Re-read from disk
func saveConfig() async throws
func addCommand(_ command: Command) async throws
func removeCommand(id: String) async throws
func updateCommand(_ command: Command) async throws
```

### Session Control
```
func startSession(commandId: String) async throws
func stopSession(commandId: String) async throws
func restartSession(commandId: String) async throws
```

**startSession logic:**
1. Get command by ID
2. Check if already running via TmuxService
3. If running, throw error or no-op
4. Call `tmuxService.startSession(for: command)`
5. Update `sessionStates[commandId].isRunning = true`
6. Set `lastStartTime = Date()`
7. Reset `consecutiveFailures = 0`

**stopSession logic:**
1. Get command by ID
2. Call `tmuxService.killSession(name: command.sessionName, host: command.host)`
3. Update state: `isRunning = false`, `lastExitTime = Date()`
4. Set `restartPaused = true` to prevent auto-restart after manual stop

### Status Refresh
```
func refreshAllStatuses() async
func refreshStatus(commandId: String) async
```

**refreshAllStatuses:**
1. For each unique host (including nil for local):
   - Call `tmuxService.listSessions(host:)`
   - Match sessions by name to commands
2. Update `isRunning` for each command
3. Detect sessions that stopped since last check
4. Trigger auto-restart logic for stopped sessions

### Output Retrieval
```
func getOutput(commandId: String, lines: Int = 10) async throws -> [String]
```
Calls TmuxService.captureOutput and updates `sessionStates[commandId].lastOutput`.

---

## Polling Mechanism

### Timer Setup
- Use `Timer.publish` or an async Task with sleep
- Poll interval: 3 seconds (configurable)
- Only poll when app is active (not needed if always checking?)

### Poll Cycle
1. Call `refreshAllStatuses()`
2. For any session that changed from running to stopped:
   - Check auto-restart eligibility
   - Either restart or mark as paused

### Efficiency Considerations
- Batch SSH calls per host to reduce connections
- Cache host connectivity status briefly
- Skip polling for hosts that are unreachable

---

## Auto-Restart Logic

### When Session Stops (detected during poll)

1. Check if command has `autoRestart.enabled`
2. If not enabled, just update state and return
3. Check if `restartPaused` (user manually stopped or max retries)
4. Calculate if session ran "long enough" to reset failure count:
   - If `lastStartTime` to `lastExitTime` > 30 seconds: reset `consecutiveFailures = 0`
5. Increment `consecutiveFailures`
6. If `consecutiveFailures >= maxRetries`:
   - Set `restartPaused = true`
   - Send notification to user
   - Return without restarting
7. Schedule restart after `retryDelaySeconds`:
   - Use `Task.sleep` or dispatch after
   - Then call `startSession(commandId:)`

### Notification Content
Title: "bgcli: Session Failed"
Body: "<Command Name> has failed {N} times and auto-restart has been paused."
Action: Clicking notification could open the app

### Resetting Restart
User can manually restart a paused session:
```
func resumeAutoRestart(commandId: String) async throws
```
Sets `restartPaused = false`, `consecutiveFailures = 0`, then starts session.

---

## State Access for UI

### Computed Accessors
```
func state(for commandId: String) -> SessionState
func command(for id: String) -> Command?
func isRunning(_ commandId: String) -> Bool
```

### Combined View Model
```
struct CommandWithState: Identifiable {
    let command: Command
    let state: SessionState
}

var commandsWithState: [CommandWithState]
```
Convenience for UI to iterate.

---

## Verification
1. Manager loads config on init and creates states for each command
2. `startSession` creates tmux session and updates state
3. `stopSession` kills session and updates state
4. Polling detects when external process ends
5. Auto-restart triggers after session crash (test with `exit 1`)
6. Auto-restart pauses after max failures
7. Notification appears when restart pauses
8. Manual restart clears paused state

## Notes
- Use `@MainActor` to ensure UI updates happen on main thread
- Consider debouncing rapid state changes
- Handle race conditions between user actions and polling
- Log important events for debugging (restart attempts, failures, etc.)
