# 09: Error Handling & Polish

## Status
✅ **COMPLETE** - All error handling and edge cases implemented.

## Completed ✅
- ✅ First-launch config directory creation (AppConfig.swift)
- ✅ Empty config welcome state with auto-open settings
- ✅ "Open Config File" menu action
- ✅ macOS notifications for auto-restart failures
- ✅ Memory management (10-line output limit)
- ✅ Async Task usage throughout
- ✅ Output truncation in UI

## Implemented Features
1. ✅ Tmux not installed UI warning
2. ✅ Enhanced SSH connection error handling
3. ✅ Config corruption recovery UI
4. ✅ Duplicate command ID validation

---

## 1. Missing tmux Detection UI

**Status:** Backend detection exists (TmuxError.tmuxNotInstalled), but no proactive UI warning.

### What's Missing
- No proactive check on app launch to verify tmux is installed
- Errors only surface when user tries to start a session
- No helpful UI guidance in menu bar when tmux is missing

### Implementation

Add to `SessionManager`:
```swift
@Published var isTmuxInstalled: Bool = true

private func checkTmuxInstalled() async {
    let exists = await Shell.runQuiet("which tmux")
    await MainActor.run {
        self.isTmuxInstalled = exists
    }
}
```

Call in `loadInitialConfig()` before starting polling.

### UI Changes

In `MenuContentView.swift`, add warning section when tmux missing:
```swift
if !sessionManager.isTmuxInstalled {
    Section {
        Label("tmux not installed", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        Button("How to Install") {
            NSWorkspace.shared.open(URL(string: "https://github.com/tmux/tmux/wiki/Installing")!)
        }
    }
    Divider()
}
```

---

## 2. Enhanced SSH Connection Error Handling

**Status:** Basic SSH validation exists, but errors are generic and not command-specific.

### Current State
- Shell.swift validates host characters and sets ConnectTimeout
- SessionManager has global `lastError` but not per-command errors
- No parsing of specific SSH error types
- No UI display of connection errors in command submenus

### What's Missing
- Per-command error tracking in SessionState
- Parsing SSH stderr for specific error patterns
- Display of errors in command submenus
- Temporary "host unreachable" marking to avoid retry spam

### Implementation

**Add to SessionState.swift:**
```swift
struct SessionState {
    ...
    var lastError: String?
    var lastErrorTime: Date?
}
```

**Add SSH error parser to Shell.swift:**
```swift
static func parseSSHError(_ stderr: String) -> String? {
    if stderr.contains("Connection refused") {
        return "Host unreachable (connection refused)"
    } else if stderr.contains("Permission denied") {
        return "SSH authentication failed"
    } else if stderr.contains("Connection timed out") {
        return "Connection timed out"
    } else if stderr.contains("Could not resolve hostname") {
        return "Host not found"
    }
    return nil
}
```

**Update SessionManager error handling:**
When `startSession` or `TmuxService` operations fail, capture the error:
```swift
do {
    try await TmuxService.startSession(for: command)
} catch {
    var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
    state.lastError = error.localizedDescription
    state.lastErrorTime = Date()
    sessionStates[commandId] = state
    throw error
}
```

**Update CommandMenuSection.swift:**
```swift
if let error = state.lastError {
    Section {
        Label(error, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        if let errorTime = state.lastErrorTime {
            Text(errorTime, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

### Auto-Restart Logic
- Don't auto-restart if last error was within 60 seconds and was SSH-related
- Consider SSH errors as connection failures, not command failures
- Show different messaging for connection vs command failures

---

## 3. Config Corruption Recovery

**Status:** ConfigError.invalidJSON exists but no UI to recover.

### Current Behavior
When config.json has invalid JSON, AppConfig.load() throws ConfigError.invalidJSON but there's no UI to help the user recover.

### What's Missing
- Error alert when config fails to load
- Option to view the corrupted file
- Option to reset to default config
- Backup of corrupted config before reset

### Implementation

Add to `SessionManager.loadInitialConfig()`:
```swift
do {
    try await loadConfig()
    startPolling()
    await refreshAllStatuses()
} catch let error as ConfigError {
    await handleConfigError(error)
} catch {
    recordError(error)
}
```

Add new method:
```swift
func handleConfigError(_ error: ConfigError) async {
    await MainActor.run {
        let alert = NSAlert()
        alert.messageText = "Configuration Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Open Config File")
        alert.addButton(withTitle: "Reset to Default")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(AppConfig.configFilePath)
        case .alertSecondButtonReturn:
            Task { await self.resetConfig() }
        default:
            NSApplication.shared.terminate(nil)
        }
    }
}

func resetConfig() async {
    // Backup corrupted config
    let backupPath = AppConfig.configDirectory
        .appendingPathComponent("config.json.backup.\(Date().timeIntervalSince1970)")
    try? FileManager.default.copyItem(
        at: AppConfig.configFilePath,
        to: backupPath
    )

    // Create fresh config
    let defaultConfig = AppConfig.createDefaultConfig()
    try? defaultConfig.save()
    try? await loadConfig()
}
```

---

## 4. Duplicate Command ID Validation

**Status:** Not currently validated. Users could manually create duplicate IDs in config.json.

### Risk
Duplicate IDs would cause dictionary collisions in SessionManager.sessionStates, leading to wrong state being displayed or commands not being controllable.

### Implementation

Add validation to `AppConfig.load()`:
```swift
static func load() throws -> AppConfig {
    // ... existing file loading code ...

    let decoder = JSONDecoder()
    let config = try decoder.decode(AppConfig.self, from: data)

    // Validate no duplicate IDs
    let ids = config.commands.map { $0.id }
    let uniqueIds = Set(ids)
    if ids.count != uniqueIds.count {
        let duplicates = Dictionary(grouping: ids, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
        throw ConfigError.duplicateCommandIds(Array(duplicates))
    }

    return config
}
```

Add new error case:
```swift
enum ConfigError: Error, LocalizedError {
    ...
    case duplicateCommandIds([String])

    var errorDescription: String? {
        switch self {
        ...
        case .duplicateCommandIds(let ids):
            return "Duplicate command IDs found: \(ids.joined(separator: ", "))"
        }
    }
}
```

Handle in SessionManager like other config errors (show alert with option to open/reset).

---

## Edge Cases Checklist

| Scenario | Status | Notes |
|----------|--------|-------|
| tmux not installed | ✅ Done | Shows warning UI with install link |
| Config file corrupted | ✅ Done | Alert with open/reset options |
| Config file missing | ✅ Done | Auto-creates empty config |
| SSH host unreachable | ✅ Done | Per-command error display with timestamp |
| Session killed externally | ✅ Done | Polling detects and updates state |
| tmux server not running | ✅ Done | Returns empty list gracefully |
| Duplicate command IDs | ✅ Done | Validates on load, clear error message |
| Very long command output | ✅ Done | Truncated to 10 lines |
| Empty config on launch | ✅ Done | Auto-opens settings window |
| App launched at login | ✅ Done | Works correctly |
| Auto-restart failures | ✅ Done | Notifications + UI state |
| Memory leaks | ✅ Done | Output history limited |

---

## Verification
1. ✅ tmux missing: Show warning UI with install link
2. ✅ Config corruption: Alert with open/reset options
3. ✅ SSH errors: Display per-command in submenu with timestamp
4. ✅ Duplicate IDs: Validate and show clear error message

## Notes
- All error handling and edge cases implemented
- Clear, actionable error messages throughout
- App is production-ready from error handling perspective
- Optional enhancement (SSH auto-restart prevention) moved to todo 10
