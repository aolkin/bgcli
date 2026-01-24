//
//  Shell.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

enum ShellError: Error, LocalizedError {
    case processLaunchFailed(Error)
    case sshConnectionFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .processLaunchFailed(let error):
            return "Failed to launch process: \(error.localizedDescription)"
        case .sshConnectionFailed:
            return "SSH connection failed"
        case .timeout:
            return "Command timed out"
        }
    }
}

struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    
    var succeeded: Bool {
        exitCode == 0
    }
    
    var output: String {
        stdout + stderr
    }
}

enum Shell {
    static func run(
        _ command: String,
        host: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ShellResult {
        func shellEscape(_ string: String) -> String {
            return string.replacingOccurrences(of: "'", with: "'\\''")
        }

        if let host = host {
            let invalidChars = CharacterSet(charactersIn: ";|&$`\\\"<>(){}[]")
            if host.rangeOfCharacter(from: invalidChars) != nil {
                throw ShellError.sshConnectionFailed
            }
        }

        let actualCommand: String
        if let host = host {
            let remoteCommand: String
            if let workingDirectory = workingDirectory {
                remoteCommand = "cd '\(shellEscape(workingDirectory))' && \(command)"
            } else {
                remoteCommand = command
            }

            actualCommand = "ssh -o BatchMode=yes -o ConnectTimeout=10 \(host) '\(shellEscape(remoteCommand))'"
        } else {
            actualCommand = command
        }

        // Default timeout for remote commands (15 seconds for responsiveness)
        let effectiveTimeout = timeout ?? (host != nil ? 15.0 : nil)

        return try await withCheckedThrowingContinuation { continuation in
            // Thread-safe state holder
            final class ResumeState: @unchecked Sendable {
                let lock = NSLock()
                var hasResumed = false
                var timedOut = false
                var timeoutTimer: DispatchSourceTimer?

                func markTimeout() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if !hasResumed {
                        timedOut = true
                        return true
                    }
                    return false
                }

                func checkTimedOut() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    return timedOut
                }

                func tryResume(_ action: () -> Void) {
                    lock.lock()
                    defer { lock.unlock() }

                    if !hasResumed {
                        hasResumed = true
                        action()
                    }
                }

                func cancelTimer() {
                    lock.lock()
                    defer { lock.unlock() }
                    timeoutTimer?.cancel()
                    timeoutTimer = nil
                }
            }

            let state = ResumeState()
            let process = Process()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", actualCommand]

            if let workingDirectory = workingDirectory, host == nil {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            var processEnvironment = ProcessInfo.processInfo.environment

            // Add Homebrew paths as fallback in case shell config doesn't include them
            let homebrewPaths = [
                "/opt/homebrew/bin",      // Apple Silicon
                "/opt/homebrew/sbin",
                "/usr/local/bin",         // Intel Mac
                "/usr/local/sbin"
            ]

            let currentPath = processEnvironment["PATH"] ?? ""
            let pathComponents = currentPath.split(separator: ":").map(String.init)
            var newPathComponents = homebrewPaths.filter { !pathComponents.contains($0) }
            newPathComponents.append(contentsOf: pathComponents)
            processEnvironment["PATH"] = newPathComponents.joined(separator: ":")

            if let environment = environment {
                processEnvironment.merge(environment) { _, new in new }
            }
            process.environment = processEnvironment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Setup timeout timer if specified
            if let timeout = effectiveTimeout {
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    // Mark as timed out and terminate process
                    // The terminationHandler will do the actual cleanup and resume
                    if state.markTimeout() {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                }
                timer.resume()
                state.timeoutTimer = timer
            }

            process.terminationHandler = { process in
                state.cancelTimer()

                // Read output first (before acquiring lock)
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                // Check if this was a timeout (before acquiring lock in tryResume)
                let timedOut = state.checkTimedOut()

                state.tryResume {
                    if timedOut {
                        continuation.resume(throwing: ShellError.timeout)
                    } else {
                        continuation.resume(returning: ShellResult(
                            stdout: stdout,
                            stderr: stderr,
                            exitCode: process.terminationStatus
                        ))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                state.cancelTimer()

                state.tryResume {
                    continuation.resume(throwing: ShellError.processLaunchFailed(error))
                }
            }
        }
    }
    
    static func runQuiet(_ command: String, host: String? = nil) async -> Bool {
        do {
            let result = try await run(command, host: host)
            return result.succeeded
        } catch {
            return false
        }
    }

    static func parseSSHError(_ stderr: String) -> String? {
        if stderr.contains("Connection refused") {
            return "Host unreachable (connection refused)"
        } else if stderr.contains("Permission denied") {
            return "SSH authentication failed"
        } else if stderr.contains("Connection timed out") {
            return "Connection timed out"
        } else if stderr.contains("Could not resolve hostname") {
            return "Host not found"
        }
        return nil
    }
    
    static func runLines(
        _ command: String,
        host: String? = nil
    ) async throws -> [String] {
        let result = try await run(command, host: host)
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
