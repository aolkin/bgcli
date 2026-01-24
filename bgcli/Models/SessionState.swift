//
//  SessionState.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

/// Represents the execution state of a session
enum SessionExecutionState: Equatable {
    case stopped
    case starting
    case running
    case stopping
}

/// Tracks the runtime state of a command's tmux session (not persisted to disk)
struct SessionState: Identifiable {
    let commandId: String
    var executionState: SessionExecutionState
    var lastOutput: [String]
    var consecutiveFailures: Int
    var lastStartTime: Date?
    var lastExitTime: Date?
    var restartPaused: Bool
    var lastError: String?
    var lastErrorTime: Date?
    var isConnectionError: Bool?

    /// Convenience computed properties for backward compatibility
    var isRunning: Bool {
        executionState == .running
    }

    var isStarting: Bool {
        executionState == .starting
    }

    var isStopping: Bool {
        executionState == .stopping
    }

    /// SF Symbol name based on the current state
    var statusIcon: String {
        switch executionState {
        case .starting, .stopping:
            return "circle.dotted"  // Operation in progress
        case .running:
            return restartPaused ? "exclamationmark.circle" : "circle.fill"  // Green or yellow
        case .stopped:
            return restartPaused ? "exclamationmark.circle" : "circle"  // Yellow or gray
        }
    }

    var id: String {
        commandId
    }

    init(
        commandId: String,
        executionState: SessionExecutionState = .stopped,
        lastOutput: [String] = [],
        consecutiveFailures: Int = 0,
        lastStartTime: Date? = nil,
        lastExitTime: Date? = nil,
        restartPaused: Bool = false,
        lastError: String? = nil,
        lastErrorTime: Date? = nil,
        isConnectionError: Bool? = nil
    ) {
        self.commandId = commandId
        self.executionState = executionState
        self.lastOutput = lastOutput
        self.consecutiveFailures = consecutiveFailures
        self.lastStartTime = lastStartTime
        self.lastExitTime = lastExitTime
        self.restartPaused = restartPaused
        self.lastError = lastError
        self.lastErrorTime = lastErrorTime
        self.isConnectionError = isConnectionError
    }
}
