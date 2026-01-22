//
//  Shell.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

/// Error types that can occur during shell execution
enum ShellError: Error {
    case processLaunchFailed(Error)
    case sshConnectionFailed
    case timeout
}

/// Result of a shell command execution
struct ShellResult {
    /// Standard output from the command
    let stdout: String
    
    /// Standard error from the command
    let stderr: String
    
    /// Process exit code
    let exitCode: Int32
    
    /// Returns true if the command succeeded (exit code 0)
    var succeeded: Bool {
        exitCode == 0
    }
    
    /// Combined stdout and stderr output
    var output: String {
        stdout + stderr
    }
}

/// Utility for executing shell commands both locally and via SSH
enum Shell {
    /// Execute a shell command asynchronously
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - host: Optional SSH host for remote execution
    ///   - workingDirectory: Optional working directory for the command
    ///   - environment: Optional environment variables to set
    /// - Returns: ShellResult containing stdout, stderr, and exit code
    /// - Throws: ShellError if the process fails to launch
    static func run(
        _ command: String,
        host: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> ShellResult {
        // Helper function to escape strings for shell execution
        func shellEscape(_ string: String) -> String {
            // Escape single quotes by replacing ' with '\''
            return string.replacingOccurrences(of: "'", with: "'\\''")
        }
        
        // Validate host parameter to prevent injection
        if let host = host {
            // Basic validation: host should not contain shell metacharacters
            let invalidChars = CharacterSet(charactersIn: ";|&$`\\\"<>(){}[]")
            if host.rangeOfCharacter(from: invalidChars) != nil {
                throw ShellError.sshConnectionFailed
            }
        }
        
        // Determine the actual command to execute
        let actualCommand: String
        if let host = host {
            // SSH execution - build the remote command
            let remoteCommand: String
            if let workingDirectory = workingDirectory {
                // Build cd command with escaped directory, then execute the user command
                remoteCommand = "cd '\(shellEscape(workingDirectory))' && \(command)"
            } else {
                remoteCommand = command
            }
            
            // Wrap the entire remote command in single quotes for SSH
            // This prevents local shell interpretation while allowing remote execution
            actualCommand = "ssh -o BatchMode=yes -o ConnectTimeout=10 \(host) '\(shellEscape(remoteCommand))'"
        } else {
            // Local execution
            actualCommand = command
        }
        
        // Execute using Process
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            
            // Use zsh as the default shell (macOS default since Catalina)
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", actualCommand]
            
            // Set working directory for local execution
            if let workingDirectory = workingDirectory, host == nil {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }
            
            // Merge environment variables
            var processEnvironment = ProcessInfo.processInfo.environment
            if let environment = environment {
                processEnvironment.merge(environment) { _, new in new }
            }
            process.environment = processEnvironment
            
            // Set up pipes for stdout and stderr
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            // Handle process termination
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                
                let result = ShellResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                )
                
                continuation.resume(returning: result)
            }
            
            // Launch the process
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellError.processLaunchFailed(error))
            }
        }
    }
    
    /// Execute a shell command quietly, returning only success/failure
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - host: Optional SSH host for remote execution
    /// - Returns: True if the command succeeded (exit code 0), false otherwise
    static func runQuiet(_ command: String, host: String? = nil) async -> Bool {
        do {
            let result = try await run(command, host: host)
            return result.succeeded
        } catch {
            return false
        }
    }
    
    /// Execute a shell command and return stdout as an array of trimmed lines
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - host: Optional SSH host for remote execution
    /// - Returns: Array of trimmed output lines
    /// - Throws: ShellError if the process fails to launch
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
