//
//  SessionState.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

/// Tracks the runtime state of a command's tmux session (not persisted to disk)
struct SessionState: Identifiable {
    let commandId: String
    var isRunning: Bool
    var lastOutput: [String]
    var consecutiveFailures: Int
    var lastStartTime: Date?
    var lastExitTime: Date?
    var restartPaused: Bool
    var lastError: String?
    var lastErrorTime: Date?
    
    /// SF Symbol name based on the current state
    var statusIcon: String {
        if restartPaused {
            return "exclamationmark.circle"  // Yellow tint
        } else if isRunning {
            return "circle.fill"  // Green tint
        } else {
            return "circle"  // Gray
        }
    }
    
    var id: String {
        commandId
    }
    
    init(
        commandId: String,
        isRunning: Bool = false,
        lastOutput: [String] = [],
        consecutiveFailures: Int = 0,
        lastStartTime: Date? = nil,
        lastExitTime: Date? = nil,
        restartPaused: Bool = false,
        lastError: String? = nil,
        lastErrorTime: Date? = nil
    ) {
        self.commandId = commandId
        self.isRunning = isRunning
        self.lastOutput = lastOutput
        self.consecutiveFailures = consecutiveFailures
        self.lastStartTime = lastStartTime
        self.lastExitTime = lastExitTime
        self.restartPaused = restartPaused
        self.lastError = lastError
        self.lastErrorTime = lastErrorTime
    }
}
