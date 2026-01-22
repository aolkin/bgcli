# 08: Terminal Integration

## Objective
Enable "Open in Terminal" to attach to a tmux session in iTerm2 (or Terminal.app fallback).

## Prerequisites
- 01-project-setup complete
- 04-tmux-service complete
- 06-menu-ui complete

## Deliverables
1. Function to open iTerm2 with tmux attach command
2. Fallback to Terminal.app if iTerm2 not installed
3. Support for both local and remote (SSH) sessions

## Files to Create
- `bgcli/Utilities/TerminalLauncher.swift`

---

## TerminalLauncher

### Purpose
Opens a terminal application and runs a command to attach to a tmux session.

### Public Interface
```
static func openSession(
    sessionName: String,
    host: String?
) async throws
```

### Command to Execute

**Local session:**
```
tmux attach -t <sessionName>
```

**Remote session:**
```
ssh -t <host> tmux attach -t <sessionName>
```

The `-t` flag for SSH forces pseudo-terminal allocation, required for interactive tmux.

---

## iTerm2 Integration

### Detection
Check if iTerm2 is installed:
```
FileManager.default.fileExists(atPath: "/Applications/iTerm.app")
```

### Opening via AppleScript
Use `NSAppleScript` to tell iTerm2 to create a new window and run command:

```applescript
tell application "iTerm"
    activate
    create window with default profile command "<command>"
end tell
```

### Alternative: URL Scheme
iTerm2 supports URL schemes but they're more limited. AppleScript is more reliable.

### Swift Implementation
```
let script = """
tell application "iTerm"
    activate
    create window with default profile command "\(command)"
end tell
"""
let appleScript = NSAppleScript(source: script)
var error: NSDictionary?
appleScript?.executeAndReturnError(&error)
```

### Escaping
The command string needs proper escaping for AppleScript:
- Escape backslashes: `\` → `\\`
- Escape quotes: `"` → `\"`

---

## Terminal.app Fallback

### Opening via AppleScript
```applescript
tell application "Terminal"
    activate
    do script "<command>"
end tell
```

### Swift Implementation
Similar to iTerm2, using NSAppleScript.

---

## Implementation Flow

```
func openSession(sessionName: String, host: String?) async throws {
    let command: String
    if let host = host {
        command = "ssh -t \(host) tmux attach -t \(sessionName)"
    } else {
        command = "tmux attach -t \(sessionName)"
    }

    let escapedCommand = escapeForAppleScript(command)

    if iTermInstalled() {
        try openInITerm(command: escapedCommand)
    } else {
        try openInTerminal(command: escapedCommand)
    }
}
```

---

## Error Handling

Define `TerminalError` enum:
- `scriptExecutionFailed(String)` - AppleScript error
- `noTerminalAvailable` - Neither iTerm2 nor Terminal found (unlikely on macOS)

---

## Integration with Menu

In `CommandMenuSection`, for running sessions:
```
Button("Open in Terminal") {
    Task {
        try await TerminalLauncher.openSession(
            sessionName: command.sessionName,
            host: command.host
        )
    }
}
.disabled(!state.isRunning)
```

---

## Security Considerations

### Sandbox
If app is sandboxed, AppleScript automation requires entitlements:
- `com.apple.security.automation.apple-events`
- May need to add iTerm2 and Terminal to target apps

For initial development, run without sandbox. Add entitlements if distributing via App Store (unlikely for this utility).

### User Permission
First time running AppleScript to control another app, macOS will prompt user for permission. This is expected behavior.

---

## Verification
1. "Open in Terminal" with iTerm2 installed opens iTerm2
2. New iTerm2 window runs `tmux attach -t <session>`
3. User can interact with the session
4. With iTerm2 uninstalled, falls back to Terminal.app
5. Remote sessions open with `ssh -t` command
6. Button is disabled when session not running

## Notes
- AppleScript is the most reliable cross-terminal approach
- Could add user preference for terminal app later
- Consider adding "Detach" hint in terminal title or message
