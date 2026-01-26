# Simplify tmux/shell quoting and remove hardcoded zsh usage

Summary

`TmuxService` builds nested quoting (constructs a `zsh -l -c '...` wrapper and then escapes again) and `Shell.run` always executes `/bin/zsh -c`. This double-wrapping and hardcoded shell assumption is fragile and makes correct escaping difficult for complex commands.

Goal

Reduce quoting complexity by using argument-based Process invocation when possible, make remote command construction safer for `ssh`, and make the login shell configurable rather than hardcoding `/bin/zsh`.

Proposed Work

- Add an alternative `Shell.run` API that accepts an executable and an `[String]` arguments array and uses `Process.executableURL` + `arguments` (avoids shell parsing when shell features aren't needed).
- For remote execution (`ssh`), prefer invoking `ssh` with an argument vector and pass the remote command as a single string only when required — replace fragile `zsh -l -c` wrapping where possible.
- Add configuration for preferred shell (default to `SHELL` env or fallback to `/bin/sh`), and only use a login shell (`-l`) when explicitly required by command semantics.
- Simplify `TmuxService.startSession` so it builds the inner command once and avoids multiple layers of escaping.

Tasks

- [ ] Extend `Shell.run` to support array-based command execution and update call sites.
- [ ] Update `TmuxService.startSession` to use the safer API and reduce nested `zsh -l -c` wrapping.
- [ ] Add config option for default shell (SHELL env fallback) and use it consistently.
- [ ] Add tests for tricky command strings (quotes, newlines, backticks) both locally and via ssh to ensure behavior is correct.

Acceptance Criteria

- Commands with complex quoting execute correctly in tests.
- No hardcoded `/bin/zsh` usage remains unless explicitly requested in config.
- Tmux session startup code is simpler and easier to reason about.

Relevant files

- bgcli/Utilities/Shell.swift
- bgcli/Services/TmuxService.swift

Estimated effort: 2 days
