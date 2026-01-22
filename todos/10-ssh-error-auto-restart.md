# 10: SSH Error Auto-Restart Prevention

## Status
Optional enhancement to prevent auto-restart spam on persistent SSH connection errors.

## Problem
Currently, when a command fails to start due to SSH errors (connection refused, timeout, auth failure), the auto-restart logic will repeatedly attempt to restart at the configured interval. This can lead to:
- Spamming failed connection attempts
- Confusing UX when the issue is infrastructure (host down, network issue)
- Unnecessary load on remote systems

## Goal
Distinguish between connection failures (SSH errors) and command failures (command exited), and handle auto-restart differently for each case.

## Implementation

### 1. Categorize Error Types in SessionState
Add a field to track whether the last error was a connection error vs command failure.

**File:** `SessionState.swift`
- Add `isConnectionError: Bool?` field
- Update init with new parameter

### 2. Detect SSH Errors in SessionManager
When catching errors in `startSessionLocked`, determine if it's an SSH connection error.

**File:** `SessionManager.swift`
- Use `Shell.parseSSHError()` to detect SSH-specific errors
- Set `state.isConnectionError = true` for SSH errors
- Set `state.isConnectionError = false` for other errors

### 3. Suppress Auto-Restart for Recent SSH Errors
In `handleAutoRestart`, skip restart if there was a recent SSH connection error.

**File:** `SessionManager.swift`
- Check if `state.isConnectionError == true`
- Check if `state.lastErrorTime` was within last 60 seconds
- If both true, set `state.restartPaused = true` and return early
- Show different notification message for connection failures vs command failures

### 4. Update UI Messaging
Distinguish between connection and command failures in the UI.

**File:** `CommandMenuSection.swift`
- Show different icon or color for connection errors
- Optional: Add "Test Connection" button for SSH errors
- Resume button should work normally to retry after fixing connection

## Acceptance Criteria
- SSH connection errors (refused, timeout, auth failed) don't spam restart attempts
- Auto-restart pauses after first SSH error with clear messaging
- Command failures (process exited) continue to auto-restart as configured
- User can manually resume to retry connection after fixing issues
- UI clearly indicates whether failure was connection or command-related

## Notes
- This is a "nice to have" enhancement for production quality
- Makes the app more resilient to infrastructure issues
- Improves UX by avoiding confusing repeated connection attempts
