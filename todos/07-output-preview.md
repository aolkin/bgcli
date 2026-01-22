# 07: Output Preview

## Objective
Show recent terminal output in a submenu that appears when hovering over a command.

## Prerequisites
- 01-project-setup complete
- 05-session-manager complete
- 06-menu-ui complete (integrates with CommandMenuSection)

## Deliverables
1. Output preview as submenu content
2. Last ~10 lines shown in monospace text
3. Copy button in submenu

## Approach
Use pure SwiftUI Menu/submenu. Output appears as text items within the command's submenu.

**Known Limitations:**
- Menu items may truncate long lines
- No scrolling (if output exceeds menu height)
- Limited styling options

If these become problematic, upgrade to AppKit NSMenu with custom view.

---

## Integration in CommandMenuSection

The command's submenu structure becomes:

```
Menu("Command Name") {
    // Output section
    Section {
        ForEach(outputLines) { line in
            Text(line)
                .font(.system(.caption, design: .monospaced))
        }
    }

    Divider()

    // Actions
    Button("Copy Output") { ... }
    Button("Start/Stop") { ... }
    Button("Open in Terminal") { ... }
}
```

### Output as Menu Items
Each line of output becomes a separate menu item (disabled/non-interactive):
- Use `Text(line)` or `Button(line) {}.disabled(true)`
- Apply monospace font
- Limit to ~10 most recent lines

### Fetching Output
Output should be fetched/cached in SessionState:
- Poll updates `lastOutput` in SessionState
- Or fetch on-demand when menu opens (harder to detect in SwiftUI)

Simpler: SessionManager's polling already captures output periodically.

### Empty State
If no output available:
```
Text("No output yet")
    .foregroundColor(.secondary)
```

---

## Copy Functionality

Add "Copy Output" button that copies all lines:
```
Button("Copy Output") {
    let text = state.lastOutput.joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
.disabled(state.lastOutput.isEmpty)
```

---

## Handling Long Lines

Options for lines that exceed menu width:
1. **Truncate** - Default behavior, adds "..."
2. **Wrap** - Not supported in menu items
3. **Limit line length** - Truncate at ~60 chars before displaying

Recommend option 3 for now:
```
Text(line.prefix(60) + (line.count > 60 ? "..." : ""))
```

---

## SessionManager Changes

Ensure polling captures output for all running sessions:

In `refreshAllStatuses()`:
```
for command in commands where state.isRunning {
    state.lastOutput = try await tmuxService.captureOutput(
        sessionName: command.sessionName,
        lines: 10,
        host: command.host
    )
}
```

Consider: Only fetch output for sessions that have the menu open? Hard to detect. Simpler to always fetch.

---

## Verification
1. Hovering over command shows submenu with output lines
2. Output appears in monospace font
3. Long lines are truncated reasonably
4. "Copy Output" copies text to clipboard
5. Empty state shows "No output yet"
6. Output updates as session runs (on next poll cycle)

## Future Upgrade Path
If limitations are too restrictive:
- Switch to AppKit NSMenu
- Use NSMenuItem with custom NSView
- Embed scrollable NSTextView for output
- Gives full control over sizing and scrolling
