//
//  AppConfig.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation

/// Configuration errors
enum ConfigError: Error, LocalizedError {
    case fileNotReadable
    case invalidJSON(Error)
    case writeFailed(Error)
    case duplicateCommandIds([String])

    var errorDescription: String? {
        switch self {
        case .fileNotReadable:
            return "Config file could not be read"
        case .invalidJSON(let error):
            return "Invalid JSON in config file: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to write config file: \(error.localizedDescription)"
        case .duplicateCommandIds(let ids):
            return "Duplicate command IDs found: \(ids.joined(separator: ", "))"
        }
    }
}

/// Manages loading and saving the application configuration
struct AppConfig: Codable {
    var commands: [Command]
    
    /// Config directory path: ~/.config/bgcli/
    static var configDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("bgcli")
    }
    
    /// Config file path: ~/.config/bgcli/config.json
    static var configFilePath: URL {
        configDirectory.appendingPathComponent("config.json")
    }
    
    /// Load config from disk, create default if missing
    static func load() throws -> AppConfig {
        let fileManager = FileManager.default
        
        // Create config directory if it doesn't exist
        if !fileManager.fileExists(atPath: configDirectory.path) {
            try fileManager.createDirectory(
                at: configDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        // If config file doesn't exist, create default and save it
        if !fileManager.fileExists(atPath: configFilePath.path) {
            let defaultConfig = createDefaultConfig()
            try defaultConfig.save()
            return defaultConfig
        }
        
        // Read and parse config file
        guard let data = try? Data(contentsOf: configFilePath) else {
            throw ConfigError.fileNotReadable
        }
        
        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(AppConfig.self, from: data)

            // Validate no duplicate IDs
            let ids = config.commands.map { $0.id }
            let uniqueIds = Set(ids)
            if ids.count != uniqueIds.count {
                let duplicates = Dictionary(grouping: ids, by: { $0 })
                    .filter { $0.value.count > 1 }
                    .keys
                throw ConfigError.duplicateCommandIds(Array(duplicates))
            }

            return config
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.invalidJSON(error)
        }
    }
    
    /// Write current config to disk
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(self)
            try data.write(to: Self.configFilePath, options: .atomic)
        } catch {
            throw ConfigError.writeFailed(error)
        }
    }
    
    /// Returns a default (empty) configuration
    static func createDefaultConfig() -> AppConfig {
        AppConfig(commands: [])
    }
    
    init(commands: [Command] = []) {
        self.commands = commands
    }
}
