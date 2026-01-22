//
//  TerminalLauncher.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

enum TerminalLauncherError: Error, LocalizedError {
    case invalidArgument(String)
    case scriptExecutionFailed(String)
    case noTerminalAvailable

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message):
            return message
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
    private static let allowedHostCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_@[]:"
    )
    private static let invalidSessionCharacters = CharacterSet.controlCharacters

    static func openSession(
        sessionName: String,
        host: String?
    ) async throws {
        try validateSessionName(sessionName)
        if let host = host {
            try validateHost(host)
        }
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
        let quotedSession = shellQuote(sessionName)
        if let host = host {
            let quotedHost = shellQuote(host)
            return "ssh -t -- \(quotedHost) tmux attach -t \(quotedSession)"
        }
        return "tmux attach -t \(quotedSession)"
    }

    private static func shellQuote(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func escapeForAppleScript(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
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
        let result = appleScript.executeAndReturnError(&error)
        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw TerminalLauncherError.scriptExecutionFailed(message)
        }
    }

    private static func validateHost(_ host: String) throws {
        guard !host.isEmpty else {
            throw TerminalLauncherError.invalidArgument("Invalid host value for terminal session")
        }
        guard host.rangeOfCharacter(from: allowedHostCharacters.inverted) == nil else {
            throw TerminalLauncherError.invalidArgument("Invalid host value for terminal session")
        }
        if host.hasPrefix("-") {
            throw TerminalLauncherError.invalidArgument("Invalid host value for terminal session")
        }
    }

    private static func validateSessionName(_ sessionName: String) throws {
        guard !sessionName.isEmpty else {
            throw TerminalLauncherError.invalidArgument("Invalid session name for terminal session")
        }
        if sessionName.rangeOfCharacter(from: invalidSessionCharacters) != nil {
            throw TerminalLauncherError.invalidArgument("Invalid session name for terminal session")
        }
    }
}
