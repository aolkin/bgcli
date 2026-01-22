# 04: tmux Service

## Objective
Create a service that wraps tmux CLI operations for session management, supporting both local and remote (SSH) scenarios.

## Prerequisites
- 01-project-setup complete
- 02-models complete (for `Command` type)
- 03-shell-utility complete

## Deliverables
1. `TmuxService` with all core tmux operations
2. Support for local and SSH-based tmux
3. Proper parsing of tmux output formats

## Files to Create
- `bgcli/Services/TmuxService.swift`

---

## TmuxService

### Purpose
Encapsulates all tmux CLI interactions. Handles the translation between app concepts and tmux commands.

### Design
- Stateless service (no stored state)
- All methods are async and may throw
- Takes `host: String?` parameter to support remote execution
- Uses `Shell` utility for actual command execution

### Public Interface

#### Session Discovery
```
func listSessions(host: String? = nil) async throws -> [TmuxSession]
```

**TmuxSession struct:**
| Property | Type | Description |
|----------|------|-------------|
| `name` | `String` | Session name |
| `isAttached` | `Bool` | Whether a client is attached |
| `windowCount` | `Int` | Number of windows |

**tmux command:**
```
tmux list-sessions -F "#{session_name}\t#{session_attached}\t#{session_windows}"
```

**Behavior:**
- Returns empty array if tmux server not running (not an error)
- Parse tab-separated output
- Filter to only sessions with `bgcli-` prefix

#### Session Existence Check
```
func hasSession(name: String, host: String? = nil) async -> Bool
```

**tmux command:**
```
tmux has-session -t <name>
```
Returns true if exit code 0, false otherwise.

#### Start Session
```
func startSession(
    name: String,
    command: String,
    workingDirectory: String?,
    environment: [String: String],
    host: String? = nil
) async throws
```

**tmux command construction:**
```
tmux new-session -d -s <name> -c <workdir> '<command>'
```

**Considerations:**
- `-d` for detached (don't attach)
- `-s` for session name
- `-c` for starting directory (if provided)
- Environment variables: use `-e KEY=VALUE` for each (tmux 3.0+)
- For older tmux, may need to prefix command with `env KEY=VALUE`
- Quote the command properly for shell execution

#### Kill Session
```
func killSession(name: String, host: String? = nil) async throws
```

**tmux command:**
```
tmux kill-session -t <name>
```

#### Capture Output
```
func captureOutput(
    sessionName: String,
    lines: Int = 10,
    host: String? = nil
) async throws -> [String]
```

**tmux command:**
```
tmux capture-pane -t <name> -p -S -<lines>
```

**Flags:**
- `-t` target session (uses first window/pane)
- `-p` print to stdout (instead of paste buffer)
- `-S -10` start capture 10 lines from bottom

**Post-processing:**
- Split output by newlines
- Trim trailing empty lines
- Return as array of strings

#### Send Keys (for future interactive features)
```
func sendKeys(
    sessionName: String,
    keys: String,
    host: String? = nil
) async throws
```

**tmux command:**
```
tmux send-keys -t <name> '<keys>'
```

Useful for sending Ctrl+C or other signals.

---

## Convenience Methods

#### Start from Command Model
```
func startSession(for command: Command) async throws
```
Extracts properties from Command and calls the main startSession method.

#### Check if Command is Running
```
func isRunning(_ command: Command) async -> Bool
```
Calls `hasSession(name: command.sessionName, host: command.host)`

---

## Error Handling

Define `TmuxError` enum:
- `sessionNotFound(String)` - session doesn't exist
- `sessionAlreadyExists(String)` - trying to create duplicate
- `tmuxNotInstalled` - tmux binary not found
- `commandFailed(String, Int32)` - tmux command failed with output and exit code

### Detecting tmux Not Installed
Before first operation, or on first failure, check:
```
which tmux
```
If not found, throw `tmuxNotInstalled`.

---

## Remote (SSH) Considerations

All commands support `host` parameter:
- When nil: run tmux locally
- When set: wrap command in `ssh <host> '<tmux command>'`

Escaping considerations:
- The tmux command itself may contain quotes
- Need to properly escape for SSH
- Consider using single quotes for outer, escape inner singles

Example for remote:
```
ssh user@host "tmux list-sessions -F '#{session_name}'"
```

---

## Verification
1. `listSessions()` returns empty array when no tmux server
2. `startSession(name: "bgcli-test", command: "sleep 60", ...)` creates session
3. `hasSession(name: "bgcli-test")` returns true after start
4. `captureOutput(sessionName: "bgcli-test")` returns output
5. `killSession(name: "bgcli-test")` terminates it
6. `hasSession(name: "bgcli-test")` returns false after kill
7. Same operations work with `host: "localhost"` if SSH configured

## Notes
- Don't store state in this service; let SessionManager track runtime state
- Handle the case where tmux server isn't running gracefully
- Consider adding a method to check tmux version for feature compatibility
- The session name should always include the `bgcli-` prefix when used
