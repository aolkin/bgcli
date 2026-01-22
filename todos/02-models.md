# 02: Data Models

## Objective
Define the core data structures for command configuration and runtime session state.

## Prerequisites
- 01-project-setup complete

## Can Parallelize With
- 03-shell-utility (no shared dependencies)

## Deliverables
1. `Command` model - represents a configured command
2. `SessionState` model - represents runtime state of a session
3. `AppConfig` model - manages loading/saving the config file
4. All models with appropriate Codable conformance

## Files to Create
- `bgcli/Models/Command.swift`
- `bgcli/Models/SessionState.swift`
- `bgcli/Models/AppConfig.swift`

---

## Command Model

### Purpose
Represents a single command configuration as stored in the JSON config file.

### Properties
| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique identifier, used in tmux session name |
| `name` | `String` | Human-readable display name |
| `command` | `String` | The shell command to execute |
| `workingDirectory` | `String?` | Optional working directory path |
| `host` | `String?` | SSH host (nil = local, e.g., `user@host.com`) |
| `autoRestart` | `AutoRestartConfig` | Restart behavior settings |
| `env` | `[String: String]` | Environment variables |

### AutoRestartConfig (nested struct)
| Property | Type | Default |
|----------|------|---------|
| `enabled` | `Bool` | `false` |
| `maxRetries` | `Int` | `5` |
| `retryDelaySeconds` | `Int` | `5` |

### Computed Properties
- `sessionName: String` - Returns `"bgcli-\(id)"` for tmux session naming
- `isRemote: Bool` - Returns `host != nil`

### Conformances
- `Codable` for JSON serialization
- `Identifiable` for SwiftUI lists
- `Equatable` for change detection

---

## SessionState Model

### Purpose
Tracks the runtime state of a command's tmux session. Not persisted to disk.

### Properties
| Property | Type | Description |
|----------|------|-------------|
| `commandId` | `String` | References the Command |
| `isRunning` | `Bool` | Whether tmux session exists |
| `lastOutput` | `[String]` | Recent output lines (up to 10) |
| `consecutiveFailures` | `Int` | For auto-restart tracking |
| `lastStartTime` | `Date?` | When session was last started |
| `lastExitTime` | `Date?` | When session last exited |
| `restartPaused` | `Bool` | True if max retries exceeded |

### Computed Properties
- `statusIcon: String` - SF Symbol name based on state:
  - Running: `circle.fill` (green tint)
  - Stopped: `circle` (gray)
  - Restart paused: `exclamationmark.circle` (yellow)

### Conformances
- `Identifiable` (using `commandId`)
- `ObservableObject` or used within an ObservableObject

---

## AppConfig Model

### Purpose
Manages loading and saving the application configuration from `~/.config/bgcli/config.json`.

### Properties
| Property | Type | Description |
|----------|------|-------------|
| `commands` | `[Command]` | List of configured commands |

### Static Properties
- `configDirectory: URL` - `~/.config/bgcli/`
- `configFilePath: URL` - `~/.config/bgcli/config.json`

### Methods
| Method | Description |
|--------|-------------|
| `static func load() throws -> AppConfig` | Load config from disk, create default if missing |
| `func save() throws` | Write current config to disk |
| `static func createDefaultConfig() -> AppConfig` | Returns empty config or sample |

### Behavior
- On `load()`:
  - Create `~/.config/bgcli/` directory if it doesn't exist
  - If config file missing, create with empty commands array
  - Parse JSON and return AppConfig
- On `save()`:
  - Encode to JSON with pretty printing
  - Write atomically to config path

### Error Handling
Define `ConfigError` enum:
- `fileNotReadable`
- `invalidJSON(Error)`
- `writeFailed(Error)`

---

## Verification
1. Create a test JSON string and verify Command decodes correctly
2. Verify SessionState initializes with correct defaults
3. Verify AppConfig.load() creates directory and file if missing
4. Verify round-trip: load → modify → save → load matches

## Notes
- Use `CodingKeys` if JSON keys differ from Swift property names
- Consider using `@Published` properties if models will be observed directly
- Keep models simple; business logic belongs in SessionManager
