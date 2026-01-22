# 06: Menu UI

## Objective
Build the main menubar interface showing all commands with status indicators and action submenus.

## Prerequisites
- 01-project-setup complete
- 02-models complete
- 05-session-manager complete

## Can Parallelize With
- 07-output-preview (independent UI component)

## Deliverables
1. `MenuContentView` - main menu structure
2. `CommandMenuSection` - per-command menu item with submenu
3. Status indicators (running/stopped/paused icons)
4. Functional start/stop/open actions

## Files to Create/Modify
- `bgcli/Views/MenuContentView.swift`
- `bgcli/Views/CommandMenuSection.swift`
- Modify `bgcliApp.swift` to use these views

---

## MenuContentView

### Purpose
The root view rendered inside the MenuBarExtra. Displays the list of commands and app-level actions.

### Structure
```
MenuContentView
├── Section: Commands
│   ├── CommandMenuSection (for each command)
│   └── ...
├── Divider
├── "Settings..." button (future)
├── Divider
└── "Quit bgcli" button
```

### Environment/State
- Access `SessionManager` via `@EnvironmentObject` or `@StateObject`
- Observe `sessionManager.commandsWithState` for the list

### Menu Item: No Commands
If `commands` is empty, show:
- "No commands configured"
- "Open Config File" button (opens in default editor)

### Menu Item: Quit
Standard quit action using `NSApplication.shared.terminate(nil)`

---

## CommandMenuSection

### Purpose
Represents a single command in the menu with its status and action submenu.

### Visual Design
Each command appears as a menu item with:
- Status icon (circle with color)
- Command name
- Submenu arrow (automatic with SwiftUI Menu)

### Status Icons (SF Symbols)
| State | Symbol | Color |
|-------|--------|-------|
| Running | `circle.fill` | Green (.green) |
| Stopped | `circle` | Gray (.secondary) |
| Restart Paused | `exclamationmark.circle.fill` | Yellow (.yellow) |

### Submenu Actions

**When Stopped:**
| Action | Description |
|--------|-------------|
| "Start" | Calls `sessionManager.startSession(commandId:)` |
| --- | Divider |
| "View Output" | Opens OutputPreviewView (if any previous output) |

**When Running:**
| Action | Description |
|--------|-------------|
| "Stop" | Calls `sessionManager.stopSession(commandId:)` |
| "Restart" | Calls `sessionManager.restartSession(commandId:)` |
| "Open in Terminal" | Opens iTerm2/Terminal (see 08-terminal-integration) |
| --- | Divider |
| "View Output" | Opens OutputPreviewView |

**When Restart Paused:**
| Action | Description |
|--------|-------------|
| "Resume & Start" | Calls `sessionManager.resumeAutoRestart(commandId:)` |
| --- | Divider |
| "View Output" | Opens OutputPreviewView |

### Remote Indicator
If command has a `host` set, show it subtly:
- Could append "(remote)" to name
- Or show a different icon
- Or show host in submenu as disabled text

### Error Handling
- Wrap actions in Task with do/catch
- On error, could show alert or just log
- Consider brief visual feedback (difficult in menu context)

---

## Integration with bgcliApp.swift

### Modify App Structure
```
@main
struct bgcliApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        MenuBarExtra("bgcli", systemImage: "terminal") {
            MenuContentView()
                .environmentObject(sessionManager)
        }
        .menuBarExtraStyle(.menu)
    }
}
```

### Menu Style
Use `.menuBarExtraStyle(.menu)` for standard dropdown menu behavior.

Alternative: `.menuBarExtraStyle(.window)` would give a custom window, but is more complex.

---

## SwiftUI Menu Patterns

### Building Menus
```
Menu {
    // submenu contents
} label: {
    Label("Command Name", systemImage: "circle.fill")
}
```

### Conditional Content
```
if state.isRunning {
    Button("Stop") { ... }
} else {
    Button("Start") { ... }
}
```

### Async Actions
```
Button("Start") {
    Task {
        do {
            try await sessionManager.startSession(commandId: command.id)
        } catch {
            // handle error
        }
    }
}
```

---

## Keyboard Shortcuts (Optional Enhancement)
Could add keyboard shortcuts to common actions:
- Cmd+Q for Quit (standard)
- Cmd+, for Settings (standard)

---

## Verification
1. Menu shows all configured commands
2. Running commands show green circle
3. Stopped commands show gray circle
4. Clicking "Start" starts the session and icon turns green
5. Clicking "Stop" stops the session and icon turns gray
6. "Open in Terminal" action is present (even if not yet implemented)
7. "View Output" action is present (even if not yet implemented)
8. Empty state shows "No commands configured"
9. Quit terminates the app

## Notes
- SwiftUI menus have limited customization compared to AppKit
- If more control needed, could use NSMenu directly
- Keep the UI simple and fast; avoid heavy computation in view body
- Test with both light and dark mode
