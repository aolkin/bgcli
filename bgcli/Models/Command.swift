//
//  Command.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

/// Represents a single command configuration as stored in the JSON config file
struct Command: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let command: String
    let workingDirectory: String?
    let host: String?
    let autoRestart: AutoRestartConfig
    let env: [String: String]
    
    /// Nested struct for auto-restart configuration
    struct AutoRestartConfig: Codable, Equatable {
        let enabled: Bool
        let maxRetries: Int
        let retryDelaySeconds: Int
        
        init(enabled: Bool = false, maxRetries: Int = 5, retryDelaySeconds: Int = 5) {
            self.enabled = enabled
            self.maxRetries = maxRetries
            self.retryDelaySeconds = retryDelaySeconds
        }
    }
    
    /// Returns the tmux session name for this command
    var sessionName: String {
        "bgcli-\(id)"
    }

    /// Returns the log file path for this command's output
    var logFilePath: String {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bgcli/logs")
        return logsDir.appendingPathComponent("\(id).log").path
    }

    /// Returns true if this command should be executed on a remote host
    var isRemote: Bool {
        host != nil
    }
    
    init(
        id: String,
        name: String,
        command: String,
        workingDirectory: String? = nil,
        host: String? = nil,
        autoRestart: AutoRestartConfig = AutoRestartConfig(),
        env: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.host = host
        self.autoRestart = autoRestart
        self.env = env
    }
}
