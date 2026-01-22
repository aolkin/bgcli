//
//  TerminalLauncher.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

enum TerminalLauncherError: Error, LocalizedError {
    case scriptExecutionFailed(String)
    case noTerminalAvailable

    var errorDescription: String? {
        switch self {
        case .scriptExecutionFailed(let message):
            return "Failed to run terminal command: \(message)"
        case .noTerminalAvailable:
            return "No supported terminal application is available"
        }
    }
}

enum TerminalLauncher {
    private static let iTermPath = "/Applications/iTerm.app"
    private static let terminalPaths = [
        "/System/Applications/Utilities/Terminal.app",
        "/Applications/Utilities/Terminal.app"
    ]

    static func openSession(
        sessionName: String,
        host: String?
    ) async throws {
        let command = buildCommand(sessionName: sessionName, host: host)
        let escapedCommand = escapeForAppleScript(command)

        if isITermAvailable {
            try runAppleScript(iTermScript(command: escapedCommand))
            return
        }

        if isTerminalAvailable {
            try runAppleScript(terminalScript(command: escapedCommand))
            return
        }

        throw TerminalLauncherError.noTerminalAvailable
    }

    private static var isITermAvailable: Bool {
        FileManager.default.fileExists(atPath: iTermPath)
    }

    private static var isTerminalAvailable: Bool {
        terminalPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func buildCommand(sessionName: String, host: String?) -> String {
        let escapedSession = shellEscape(sessionName)
        if let host = host {
            let escapedHost = shellEscape(host)
            return "ssh -t '\(escapedHost)' tmux attach -t '\(escapedSession)'"
        }
        return "tmux attach -t '\(escapedSession)'"
    }

    private static func shellEscape(_ string: String) -> String {
        string.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func escapeForAppleScript(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func iTermScript(command: String) -> String {
        """
        tell application "iTerm"
            activate
            create window with default profile command "\(command)"
        end tell
        """
    }

    private static func terminalScript(command: String) -> String {
        """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
    }

    private static func runAppleScript(_ script: String) throws {
        guard let appleScript = NSAppleScript(source: script) else {
            throw TerminalLauncherError.scriptExecutionFailed("Unable to compile AppleScript")
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw TerminalLauncherError.scriptExecutionFailed(message)
        }
    }
}
