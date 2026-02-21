# Harden SSH host validation and quoting

Summary

Inconsistent host validation and escaping exists between daemonic/Utilities/Shell.swift and daemonic/Utilities/TerminalLauncher.swift (and other call sites). That inconsistency creates an SSH command injection and formatting risk and leads to surprising behavior for edge-case hostnames (user@host:port, IPv6 literals, etc.).

Goal

Centralize and harden host validation and command escaping so all SSH command builders behave consistently and safely.

Proposed Work

- Create a single helper (e.g. `Utilities/SSHHelpers.swift`) that exposes:
  - `func validateHost(_:) throws` — canonical validation for allowed host forms (user@host, host:port, IPv4, IPv6 bracketed forms)
  - `func escapeRemoteCommand(_:) -> String` — reliable escaping used when a remote shell invocation is unavoidable
- Replace ad-hoc checks in `Shell.run`, `TerminalLauncher.validateHost`, and any Tmux/ssh builders to use the centralized helper.
- Add unit tests for malicious host strings (e.g. containing `;`, `&&`, backticks, space) and for common valid forms.

Tasks

- [ ] Design the canonical host grammar (allow `user@host[:port]`, bracketed IPv6, hostnames, and optional port).
- [ ] Implement `SSHHelpers` with validation and escaping utilities.
- [ ] Replace existing checks in `daemonic/Utilities/Shell.swift` and `daemonic/Utilities/TerminalLauncher.swift` to use the helper.
- [ ] Audit `daemonic/Services/TmuxService.swift` for any additional remote-command builders and update them.
- [ ] Add unit tests and update README with accepted host formats.

Acceptance Criteria

- All SSH callers use the centralized validator.
- Test suite covers malicious input and the common valid host forms.
- Invalid host strings fail fast with a clear, deterministic error.

Relevant files

- daemonic/Utilities/Shell.swift
- daemonic/Utilities/TerminalLauncher.swift
- daemonic/Services/TmuxService.swift

Estimated effort: 1–2 days
