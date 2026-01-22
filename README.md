# bgcli - macOS Menubar Background Process Manager

## Overview
A SwiftUI menubar app that manages background CLI processes via tmux, supporting both local and remote (SSH) sessions.

## Detailed Task Plans
See `todos/` directory for step-by-step implementation plans:

| File | Description |
|------|-------------|
| `00-overview.md` | Dependency graph, parallelization opportunities |
| `01-project-setup.md` | Xcode project, MenuBarExtra setup |
| `02-models.md` | Command, SessionState, AppConfig models |
| `03-shell-utility.md` | Async shell execution (local + SSH) |
| `04-tmux-service.md` | tmux CLI wrapper |
| `05-session-manager.md` | Session orchestration, polling, auto-restart |
| `06-menu-ui.md` | Main menu with command list |
| `07-output-preview.md` | Output in submenu (SwiftUI) |
| `08-terminal-integration.md` | Open iTerm2/Terminal.app |
| `09-error-handling-polish.md` | Edge cases, notifications, first-launch |

## Key Decisions
- **macOS 13+** minimum (MenuBarExtra API)
- **SSH keys only** - no password prompt support
- **iTerm2** for attaching (fallback to Terminal.app)
- **Pure SwiftUI** for output preview (submenu with text items)
- **Bundle ID**: `dev.olkin.bgcli`
- **Config location**: `~/.config/bgcli/config.json`
- **tmux prefix**: `bgcli-<command-id>`

## Execution Order

```
01-project-setup
       │
       ├──────────────┐
       ▼              ▼
02-models      03-shell-utility   ◄── parallel
       │              │
       └──────┬───────┘
              ▼
       04-tmux-service
              │
              ▼
       05-session-manager
              │
              ▼
       06-menu-ui
              │
              ▼
       07-output-preview
              │
              ▼
       08-terminal-integration
              │
              ▼
       09-error-handling-polish
```

## Verification
1. Build and run app - menubar icon appears, no dock icon
2. Create test config with simple command (e.g., `while true; do date; sleep 1; done`)
3. Start session from menu → green status icon
4. Hover to see output in submenu
5. Stop session → gray status icon
6. Test auto-restart with failing command
7. Test "Open in Terminal" opens iTerm2
8. Test remote session if SSH host available
