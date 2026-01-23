//
//  TmuxService.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

struct TmuxSession {
    let name: String
    let isAttached: Bool
    let windowCount: Int
}

enum TmuxError: Error, LocalizedError {
    case sessionNotFound(String)
    case sessionAlreadyExists(String)
    case tmuxNotInstalled
    case commandFailed(String, Int32)
    
    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let name):
            return "Tmux session '\(name)' not found"
        case .sessionAlreadyExists(let name):
            return "Tmux session '\(name)' already exists"
        case .tmuxNotInstalled:
            return "tmux is not installed on the system"
        case .commandFailed(let output, let exitCode):
            return "Tmux command failed with exit code \(exitCode): \(output)"
        }
    }
}

enum TmuxService {
    private static func shellEscape(_ string: String) -> String {
        return string.replacingOccurrences(of: "'", with: "'\\''")
    }
    
    static func listSessions(host: String? = nil) async throws -> [TmuxSession] {
        let command = "tmux list-sessions -F \"#{session_name}|#{session_attached}|#{session_windows}\""

        do {
            let result = try await Shell.run(command, host: host)

            if result.exitCode != 0 {
                if result.stderr.contains("no server running") ||
                   result.stderr.contains("failed to connect to server") {
                    return []
                }
                throw TmuxError.commandFailed(result.output, result.exitCode)
            }

            let sessions = result.stdout
                .split(separator: "\n")
                .compactMap { line -> TmuxSession? in
                    let parts = line.split(separator: "|")
                    guard parts.count == 3 else { return nil }

                    let name = String(parts[0])
                    guard name.hasPrefix("bgcli-") else { return nil }

                    let isAttached = String(parts[1]) == "1"
                    let windowCount = Int(parts[2]) ?? 0

                    return TmuxSession(
                        name: name,
                        isAttached: isAttached,
                        windowCount: windowCount
                    )
                }

            return sessions
        } catch ShellError.processLaunchFailed {
            throw TmuxError.tmuxNotInstalled
        }
    }
    
    static func hasSession(name: String, host: String? = nil) async -> Bool {
        let command = "tmux has-session -t '\(shellEscape(name))'"
        return await Shell.runQuiet(command, host: host)
    }
    
    static func startSession(
        name: String,
        command: String,
        workingDirectory: String?,
        environment: [String: String],
        host: String? = nil,
        logFilePath: String? = nil
    ) async throws {
        if await hasSession(name: name, host: host) {
            throw TmuxError.sessionAlreadyExists(name)
        }

        // Create log directory and clear old log file
        if let logFilePath = logFilePath {
            let createLogDir = "mkdir -p \"$(dirname '\(shellEscape(logFilePath))')\" && rm -f '\(shellEscape(logFilePath))' && touch '\(shellEscape(logFilePath))'"
            _ = try? await Shell.run(createLogDir, host: host)
        }

        var tmuxCommand = "tmux new-session -d -s '\(shellEscape(name))'"

        if let workingDirectory = workingDirectory {
            tmuxCommand += " -c '\(shellEscape(workingDirectory))'"
        }

        // Build the command to run inside tmux
        // Run it in a login shell to get user's PATH and environment
        let finalCommand: String

        if environment.isEmpty {
            // No environment variables to set, just run in login shell
            let escapedForZsh = command.replacingOccurrences(of: "'", with: "'\\''")
            finalCommand = "zsh -l -c '\(escapedForZsh)'"
        } else {
            // Build export statements for environment variables
            var innerShellCommand = ""

            for (key, value) in environment {
                // Escape single quotes in the value for use within single quotes
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")

                // Special handling for PATH: prepend to existing PATH rather than replace
                if key == "PATH" {
                    // Use $ which will be evaluated in the inner shell
                    innerShellCommand += "export PATH='\(escapedValue)':$PATH; "
                } else {
                    innerShellCommand += "export \(key)='\(escapedValue)'; "
                }
            }

            innerShellCommand += command

            // Escape the inner command for the zsh -l -c '...' wrapper
            let escapedForZsh = innerShellCommand.replacingOccurrences(of: "'", with: "'\\''")
            finalCommand = "zsh -l -c '\(escapedForZsh)'"
        }

        let escapedCommand = shellEscape(finalCommand)
        tmuxCommand += " '\(escapedCommand)'"

        // Chain pipe-pane command atomically to capture output from the very beginning
        // Using \; to chain tmux commands in a single invocation
        if let logFilePath = logFilePath {
            tmuxCommand += " \\; pipe-pane -t '\(shellEscape(name))' -o 'cat >> \"\(shellEscape(logFilePath))\"'"
        }

        let result = try await Shell.run(tmuxCommand, host: host)

        if !result.succeeded {
            if result.stderr.contains("not found") || result.stderr.contains("command not found") {
                throw TmuxError.tmuxNotInstalled
            }
            throw TmuxError.commandFailed(result.output, result.exitCode)
        }
    }
    
    static func killSession(name: String, host: String? = nil) async throws {
        guard await hasSession(name: name, host: host) else {
            throw TmuxError.sessionNotFound(name)
        }
        
        // Send an interrupt (Ctrl-C) to allow graceful termination via existing sendKeys helper.
        try? await sendKeys(sessionName: name, keys: "C-c", host: host)
        
        // Wait up to 10 seconds for the session to disappear on its own.
        let start = Date()
        while Date().timeIntervalSince(start) < 10 {
            if !(await hasSession(name: name, host: host)) {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        // If it's still there, kill it forcibly.
        let command = "tmux kill-session -t '\(shellEscape(name))'"
        let result = try await Shell.run(command, host: host)
        
        if !result.succeeded {
            throw TmuxError.commandFailed(result.output, result.exitCode)
        }
    }
    
    static func captureOutput(
        sessionName: String,
        lines: Int = 10,
        host: String? = nil
    ) async throws -> [String] {
        let command = "tmux capture-pane -t '\(shellEscape(sessionName))' -p -S -\(lines)"
        let result = try await Shell.run(command, host: host)
        
        if !result.succeeded {
            throw TmuxError.commandFailed(result.output, result.exitCode)
        }
        
        var outputLines = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
        
        while outputLines.last?.isEmpty == true {
            outputLines.removeLast()
        }
        
        return outputLines
    }
    
    static func sendKeys(
        sessionName: String,
        keys: String,
        host: String? = nil
    ) async throws {
        let escapedKeys = shellEscape(keys)
        let command = "tmux send-keys -t '\(shellEscape(sessionName))' '\(escapedKeys)'"
        let result = try await Shell.run(command, host: host)
        
        if !result.succeeded {
            throw TmuxError.commandFailed(result.output, result.exitCode)
        }
    }
    
    static func readLogFile(path: String, lines: Int? = nil, host: String? = nil) async throws -> [String] {
        let readCommand: String
        if let lines = lines {
            readCommand = "tail -n \(lines) '\(shellEscape(path))' 2>/dev/null || echo ''"
        } else {
            readCommand = "cat '\(shellEscape(path))' 2>/dev/null || echo ''"
        }

        let result = try await Shell.run(readCommand, host: host)

        var outputLines = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }

        while outputLines.last?.isEmpty == true {
            outputLines.removeLast()
        }

        return outputLines
    }

    static func startSession(for command: Command) async throws {
        try await startSession(
            name: command.sessionName,
            command: command.command,
            workingDirectory: command.workingDirectory,
            environment: command.env,
            host: command.host,
            logFilePath: command.logFilePath
        )
    }

    static func isRunning(_ command: Command) async -> Bool {
        await hasSession(name: command.sessionName, host: command.host)
    }
}
