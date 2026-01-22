# 03: Shell Utility

## Objective
Create a utility for executing shell commands both locally and via SSH, with proper async/await support.

## Prerequisites
- 01-project-setup complete

## Can Parallelize With
- 02-models (no shared dependencies)

## Deliverables
1. `Shell` utility struct/enum with async command execution
2. Support for both local and SSH-based execution
3. Proper error handling and output capture

## Files to Create
- `bgcli/Utilities/Shell.swift`

---

## Shell Utility

### Purpose
Provides a clean async interface for running shell commands. Abstracts the difference between local execution and SSH.

### Public Interface

#### Main Execution Function
```
static func run(
    _ command: String,
    host: String? = nil,
    workingDirectory: String? = nil,
    environment: [String: String]? = nil
) async throws -> ShellResult
```

#### ShellResult Struct
| Property | Type | Description |
|----------|------|-------------|
| `stdout` | `String` | Standard output |
| `stderr` | `String` | Standard error |
| `exitCode` | `Int32` | Process exit code |

| Computed | Type | Description |
|----------|------|-------------|
| `succeeded` | `Bool` | `exitCode == 0` |
| `output` | `String` | Combined stdout + stderr |

### Implementation Details

#### Local Execution
- Use `Process` (Foundation)
- Set `executableURL` to `/bin/zsh` or `/bin/bash`
- Pass command via `-c` argument
- Set `currentDirectoryURL` if workingDirectory provided
- Merge environment with `ProcessInfo.processInfo.environment`
- Capture stdout and stderr via `Pipe`
- Use `withCheckedThrowingContinuation` to bridge to async

#### SSH Execution
When `host` is not nil:
- Wrap command: `ssh <host> '<command>'`
- If workingDirectory provided: `ssh <host> 'cd <dir> && <command>'`
- SSH will use the user's configured keys (no password support)
- Consider adding `-o BatchMode=yes` to prevent interactive prompts
- Consider adding `-o ConnectTimeout=10` for reasonable timeout

#### Error Cases
Define `ShellError` enum:
- `processLaunchFailed(Error)` - couldn't start Process
- `sshConnectionFailed` - SSH couldn't connect
- `timeout` - if implementing timeout support

### Convenience Methods

#### Quick Check (ignores output)
```
static func runQuiet(_ command: String, host: String? = nil) async -> Bool
```
Returns true if exit code is 0, false otherwise. Never throws.

#### Output Lines
```
static func runLines(
    _ command: String,
    host: String? = nil
) async throws -> [String]
```
Returns stdout split by newlines, trimmed.

---

## Design Considerations

### Why zsh?
macOS default shell is zsh since Catalina. Using zsh ensures consistency with user expectations.

### Environment Handling
- Start with current process environment
- Overlay any custom environment variables
- This ensures PATH and other essentials are available

### SSH Considerations
- Assume SSH keys are configured (per confirmed requirements)
- Use BatchMode to fail fast if keys aren't set up
- Quote the remote command properly to handle spaces/special chars
- For complex commands, consider using heredoc-style SSH

### Testing Locally
Commands to test:
- `echo "hello"` - basic output
- `exit 1` - non-zero exit
- `sleep 1 && echo done` - delayed output
- `cd /tmp && pwd` - working directory

---

## Verification
1. `Shell.run("echo hello")` returns "hello" with exitCode 0
2. `Shell.run("exit 42")` returns exitCode 42
3. `Shell.run("pwd", workingDirectory: "/tmp")` returns "/tmp"
4. `Shell.run("echo test", host: "localhost")` works if SSH to localhost is configured
5. `Shell.runQuiet("false")` returns false
6. `Shell.runLines("echo -e 'a\nb\nc'")` returns ["a", "b", "c"]

## Notes
- Keep this utility simple and focused
- Don't add tmux-specific logic here; that belongs in TmuxService
- Consider adding a timeout parameter in the future
- For long-running commands, TmuxService will handle those differently
