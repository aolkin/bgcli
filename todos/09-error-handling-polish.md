# 09: Error Handling & Polish

## Objective
Handle edge cases gracefully, add user notifications, and create a good first-launch experience.

## Prerequisites
- All previous tasks (01-08) complete

## Deliverables
1. Graceful handling of missing tmux
2. SSH connection error handling
3. macOS notifications for failures
4. First-launch config creation
5. "Open Config" menu action
6. General polish and edge cases

---

## Missing tmux Detection

### When to Check
- On app launch
- Before any tmux operation

### User Feedback
If tmux not installed, show in menu:
```
Section {
    Label("tmux not installed", systemImage: "exclamationmark.triangle")
        .foregroundColor(.orange)
    Button("How to Install") {
        // Open URL to homebrew or tmux site
        NSWorkspace.shared.open(URL(string: "https://github.com/tmux/tmux/wiki/Installing")!)
    }
}
```

### Check Implementation
```
func isTmuxInstalled() -> Bool {
    FileManager.default.fileExists(atPath: "/opt/homebrew/bin/tmux") ||
    FileManager.default.fileExists(atPath: "/usr/local/bin/tmux") ||
    Shell.runQuiet("which tmux")
}
```

---

## SSH Connection Errors

### Types of Failures
- Host unreachable
- Authentication failed (no key)
- Connection timeout

### Detection
SSH failures show in Shell.run stderr. Parse for common patterns:
- "Connection refused"
- "Permission denied"
- "Connection timed out"
- "Could not resolve hostname"

### User Feedback
Update SessionState with error info:
```
struct SessionState {
    ...
    var lastError: String?
}
```

Show in submenu:
```
if let error = state.lastError {
    Label(error, systemImage: "exclamationmark.triangle")
        .foregroundColor(.red)
}
```

### Recovery
- Don't spam retries for connection errors
- Mark host as "unreachable" temporarily
- Allow manual retry via menu

---

## macOS Notifications

### Setup
Request notification permission on first launch:
```
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
```

### Notification Triggers

**Auto-restart paused:**
```
Title: "bgcli"
Body: "{Command Name} failed repeatedly. Auto-restart paused."
```

**Session crashed (if not auto-restarting):**
```
Title: "bgcli"
Body: "{Command Name} has stopped."
```

### Implementation
```
func sendNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil  // immediate
    )

    UNUserNotificationCenter.current().add(request)
}
```

---

## First-Launch Experience

### Config Directory Creation
On launch, ensure `~/.config/bgcli/` exists:
```
let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/bgcli")
try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
```

### Sample Config
If no config exists, create a sample:
```json
{
  "commands": []
}
```

Or with a commented example (JSON doesn't support comments, so keep it empty or add a disabled example).

### Welcome State
If commands array is empty, show helpful menu:
```
Text("No commands configured")
    .foregroundColor(.secondary)
Divider()
Button("Open Config File") { openConfig() }
Button("View Documentation") { openDocs() }
```

---

## Open Config Action

### Menu Item
```
Button("Open Config...") {
    openConfig()
}
```

### Implementation
```
func openConfig() {
    let configPath = AppConfig.configFilePath
    NSWorkspace.shared.open(configPath)
}
```

This opens in the user's default JSON/text editor.

---

## General Polish

### Menu Responsiveness
- Async operations shouldn't block menu rendering
- Use `Task { }` for all async calls from menu buttons
- Show loading states where appropriate

### Error Logging
Add simple logging for debugging:
```
func log(_ message: String) {
    #if DEBUG
    print("[bgcli] \(message)")
    #endif
}
```

Log:
- Session start/stop events
- Auto-restart attempts
- Errors encountered

### Memory Management
- Don't accumulate unbounded output history
- Clear old session states for removed commands
- Ensure polling timer is invalidated on app quit

### App Icon
- Consider adding a simple app icon
- Use SF Symbols export or simple design
- Not critical for MVP

---

## Edge Cases Checklist

| Scenario | Handling |
|----------|----------|
| tmux not installed | Show warning, install link |
| Config file corrupted | Show error, offer to reset |
| Config file missing | Create empty config |
| SSH host unreachable | Show error, don't spam retries |
| Session killed externally | Detect on poll, update state |
| tmux server not running | Handle gracefully (empty list) |
| Duplicate command IDs | Validate on config load |
| Very long command output | Truncate to last N lines |
| App launched at login | Should work (test with Login Items) |

---

## Verification
1. App handles missing tmux gracefully with helpful message
2. SSH errors show in UI, don't cause crashes
3. Notifications appear when auto-restart pauses
4. First launch creates config directory and file
5. "Open Config" opens the config file
6. Empty config shows helpful getting-started UI
7. No crashes or hangs on any edge case

## Notes
- Focus on graceful degradation over perfect error handling
- User should always understand what went wrong
- Provide actionable next steps when possible
