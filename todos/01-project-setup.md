# 01: Project Setup

## Objective
Create the Xcode project configured as a menubar-only SwiftUI application targeting macOS 13+.

## Prerequisites
- Xcode installed
- No prior tasks required (this is the foundation)

## Deliverables
1. Xcode project with correct structure
2. App configured to run as menubar-only (no dock icon)
3. Basic MenuBarExtra showing a placeholder menu
4. App builds and runs successfully

## Implementation Details

### Project Creation
- Create new Xcode project: SwiftUI App, macOS only
- Project name: `bgcli`
- Organization identifier: `dev.olkin.bgcli`
- Minimum deployment: macOS 13.0

### Info.plist Configuration
Add key to make app menubar-only (no dock icon):
- Key: `LSUIElement`
- Type: Boolean
- Value: YES

### App Entry Point Structure
The main App struct should:
- Use `@main` attribute
- Declare a `MenuBarExtra` as the primary scene
- Use a system symbol for the menubar icon (e.g., `terminal` or `apple.terminal`)
- Include a placeholder menu with "bgcli" title and "Quit" option

### Directory Structure to Create
```
bgcli/
├── bgcli/
│   ├── bgcliApp.swift
│   ├── Models/          (empty, for future)
│   ├── Services/        (empty, for future)
│   ├── Views/           (empty, for future)
│   └── Utilities/       (empty, for future)
```

### Menu Icon Options
Possible SF Symbols for the menubar:
- `terminal` - simple terminal icon
- `apple.terminal` - Apple-style terminal
- `gearshape` - generic settings/tools
- `play.rectangle` - indicates running processes

Recommend `terminal` for clarity.

## Verification
1. Build succeeds with no errors
2. App launches and shows icon in menubar
3. No dock icon appears
4. Clicking menubar icon shows placeholder menu
5. Quit option terminates the app

## Notes
- MenuBarExtra requires macOS 13+, which we've confirmed is acceptable
- The `menuBarExtraStyle` can be `.menu` for a simple dropdown
