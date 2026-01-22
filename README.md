# bgcli - macOS Menubar Background Process Manager

## Overview
A SwiftUI menubar app that manages background CLI processes via tmux, supporting both local and remote (SSH) sessions.

## Installation

### Automated Installation (Recommended)

Download and run the installation script:

```bash
curl -fsSL https://raw.githubusercontent.com/aolkin/bgcli/main/install.sh | bash
```

Requires [GitHub CLI](https://cli.github.com/) (`gh`):
```bash
brew install gh
gh auth login
```

### Manual Installation

1. Download `bgcli-macos.zip` from the [Releases](../../releases) page
2. Unzip the archive
3. **Important**: Remove the quarantine attribute to avoid "app is damaged" error:
   ```bash
   xattr -cr /path/to/bgcli.app
   ```
4. Move `bgcli.app` to your Applications folder
5. Run the app from Applications

The app is unsigned, so macOS Gatekeeper may block it initially. The command above removes the quarantine flag that causes this issue.

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
