//
//  Shell.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

enum ShellError: Error {
    case processLaunchFailed(Error)
    case sshConnectionFailed
    case timeout
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
        environment: [String: String]? = nil
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
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", actualCommand]
            
            if let workingDirectory = workingDirectory, host == nil {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }
            
            var processEnvironment = ProcessInfo.processInfo.environment
            if let environment = environment {
                processEnvironment.merge(environment) { _, new in new }
            }
            process.environment = processEnvironment
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
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
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellError.processLaunchFailed(error))
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
