//
//  SessionOperations.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

enum SessionOperationError: Error, LocalizedError {
    case sessionAlreadyRunning(String)

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyRunning(let id):
            return "Session for command '\(id)' is already running"
        }
    }
}

/// Non-MainActor service for performing blocking SSH operations in background
actor SessionOperations {
    func startSession(
        commandId: String,
        command: Command,
        resetFailureCount: Bool
    ) async throws {
        if await TmuxService.isRunning(command) {
            throw SessionOperationError.sessionAlreadyRunning(commandId)
        }

        try await TmuxService.startSession(for: command)
    }

    func stopSession(command: Command) async throws {
        try await TmuxService.killSession(name: command.sessionName, host: command.host)
    }

    func checkSessionStatus(command: Command) async -> Bool {
        await TmuxService.hasSession(name: command.sessionName, host: command.host)
    }

    func listSessions(host: String?) async throws -> [TmuxSession] {
        try await TmuxService.listSessions(host: host)
    }

    func getOutput(command: Command, lines: Int) async throws -> [String] {
        try await TmuxService.captureOutput(
            sessionName: command.sessionName,
            lines: lines,
            host: command.host
        )
    }

    func readLogFile(command: Command, lines: Int) async throws -> [String] {
        try await TmuxService.readLogFile(
            path: command.logFilePath,
            lines: lines,
            host: command.host
        )
    }
}
