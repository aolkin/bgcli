//
//  SessionManager.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation
import UserNotifications
import AppKit

enum SessionManagerError: Error, LocalizedError {
    case commandNotFound(String)
    case sessionAlreadyRunning(String)
    case notificationDenied
    
    var errorDescription: String? {
        switch self {
        case .commandNotFound(let id):
            return "Command with ID '\(id)' was not found"
        case .sessionAlreadyRunning(let id):
            return "Session for command '\(id)' is already running"
        case .notificationDenied:
            return "Notifications are disabled for bgcli"
        }
    }
}

@MainActor
final class SessionManager: ObservableObject {
    struct CommandWithState: Identifiable {
        let command: Command
        let state: SessionState
        
        var id: String {
            command.id
        }
    }
    
    private struct RestartTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private actor CommandLock {
        private var isLocked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func lock() async {
            if !isLocked {
                isLocked = true
                return
            }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            // When resumed, we now have the lock
            isLocked = true
        }

        func unlock() {
            if waiters.isEmpty {
                isLocked = false
            } else {
                let continuation = waiters.removeFirst()
                // The resumed waiter will acquire the lock when it wakes up
                continuation.resume()
            }
        }
    }
    
    @Published private(set) var commands: [Command] = []
    @Published private(set) var sessionStates: [String: SessionState] = [:]
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var isTmuxInstalled: Bool = true
    
    private static let outputLineCount = 10
    private static let failureResetInterval: TimeInterval = 30
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    
    private let pollInterval: TimeInterval
    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var restartTasks: [String: RestartTask] = [:]
    private var commandLocks: [String: CommandLock] = [:]
    private var inFlightOperations: Set<String> = []
    private var operationGenerations: [String: Int] = [:]
    private var isRefreshing = false
    private var hasRequestedNotificationPermission = false
    
    init(pollInterval: TimeInterval = 3.0) {
        self.pollInterval = pollInterval

        loadTask = Task { @MainActor [weak self] in
            await self?.loadInitialConfig()
        }
    }
    
    deinit {
        loadTask?.cancel()
        pollTask?.cancel()
        restartTasks.values.forEach { $0.task.cancel() }
    }
    
    var commandsWithState: [CommandWithState] {
        commands.map { command in
            CommandWithState(
                command: command,
                state: sessionStates[command.id] ?? SessionState(commandId: command.id)
            )
        }
    }
    
    func state(for commandId: String) -> SessionState {
        sessionStates[commandId] ?? SessionState(commandId: commandId)
    }
    
    func command(for id: String) -> Command? {
        commands.first { $0.id == id }
    }
    
    func isRunning(_ commandId: String) -> Bool {
        sessionStates[commandId]?.isRunning ?? false
    }
    
    func loadConfig() async throws {
        let config = try AppConfig.load()
        commands = config.commands
        syncSessionStates()
    }
    
    func saveConfig() async throws {
        let config = AppConfig(commands: commands)
        try config.save()
    }
    
    func addCommand(_ command: Command) async throws {
        commands.append(command)
        syncSessionStates()
        try await saveConfig()
    }
    
    func removeCommand(id: String) async throws {
        commands.removeAll { $0.id == id }
        sessionStates[id] = nil
        restartTasks[id]?.task.cancel()
        restartTasks[id] = nil
        commandLocks[id] = nil
        inFlightOperations.remove(id)
        operationGenerations[id] = nil
        try await saveConfig()
    }
    
    func updateCommand(_ command: Command) async throws {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else {
            throw SessionManagerError.commandNotFound(command.id)
        }
        commands[index] = command
        syncSessionStates()
        try await saveConfig()
    }
    
    func startSession(commandId: String, resetFailureCount: Bool = true) async throws {
        try await withCommandLock(commandId: commandId) {
            guard let command = command(for: commandId) else {
                throw SessionManagerError.commandNotFound(commandId)
            }
            try await startSessionLocked(commandId: commandId, command: command, resetFailureCount: resetFailureCount)
        }
    }
    
    func stopSession(commandId: String) async throws {
        try await withCommandLock(commandId: commandId) {
            guard let command = command(for: commandId) else {
                throw SessionManagerError.commandNotFound(commandId)
            }

            var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
            state.restartPaused = true
            restartTasks[commandId]?.task.cancel()
            restartTasks[commandId] = nil

            var killSucceeded = false
            defer {
                if killSucceeded {
                    state.isRunning = false
                    state.lastExitTime = Date()
                }
                sessionStates[commandId] = state
            }

            try await TmuxService.killSession(name: command.sessionName, host: command.host)
            killSucceeded = true
        }
    }
    
    func restartSession(commandId: String) async throws {
        try await withCommandLock(commandId: commandId) {
            guard let command = command(for: commandId) else {
                throw SessionManagerError.commandNotFound(commandId)
            }

            if await TmuxService.isRunning(command) {
                try await TmuxService.killSession(name: command.sessionName, host: command.host)
            }

            var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
            state.restartPaused = false
            sessionStates[commandId] = state

            try await startSessionLocked(commandId: commandId, command: command, resetFailureCount: true)
        }
    }
    
    func resumeAutoRestart(commandId: String) async throws {
        try await withCommandLock(commandId: commandId) {
            guard let command = command(for: commandId) else {
                throw SessionManagerError.commandNotFound(commandId)
            }

            var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
            state.restartPaused = false
            sessionStates[commandId] = state

            try await startSessionLocked(commandId: commandId, command: command, resetFailureCount: true)
        }
    }
    
    func refreshAllStatuses() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let groupedCommands = Dictionary(grouping: commands, by: { $0.host })
        
        for (host, hostCommands) in groupedCommands {
            do {
                let generationSnapshot = operationGenerations
                let sessions = try await TmuxService.listSessions(host: host)
                let runningSessions = Set(sessions.map { $0.name })
                
                for command in hostCommands {
                    await updateState(
                        for: command,
                        runningSessions: runningSessions,
                        generationSnapshot: generationSnapshot
                    )
                }
            } catch {
                recordError(error)
            }
        }
    }
    
    func refreshStatus(commandId: String) async {
        guard let command = command(for: commandId) else { return }
        
        do {
            let generationSnapshot = operationGenerations
            let sessions = try await TmuxService.listSessions(host: command.host)
            let runningSessions = Set(sessions.map { $0.name })
            
            await updateState(
                for: command,
                runningSessions: runningSessions,
                generationSnapshot: generationSnapshot
            )
        } catch {
            recordError(error)
        }
    }
    
    func getOutput(commandId: String, lines: Int? = nil) async throws -> [String] {
        try await withCommandLock(commandId: commandId) {
            guard let command = command(for: commandId) else {
                throw SessionManagerError.commandNotFound(commandId)
            }
            
            let linesToFetch = lines ?? Self.outputLineCount
            let output = try await TmuxService.captureOutput(
                sessionName: command.sessionName,
                lines: linesToFetch,
                host: command.host
            )
            
            var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
            state.lastOutput = output
            sessionStates[commandId] = state
            
            return output
        }
    }
    
    private func loadInitialConfig() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await loadConfig()
            await checkTmuxInstalled()
            startPolling()
            await refreshAllStatuses()
        } catch let error as ConfigError {
            await handleConfigError(error)
        } catch {
            recordError(error)
        }
    }
    
    private func syncSessionStates() {
        var updatedStates: [String: SessionState] = [:]
        
        for command in commands {
            if let existingState = sessionStates[command.id] {
                updatedStates[command.id] = existingState
            } else {
                updatedStates[command.id] = SessionState(commandId: command.id)
            }
        }
        
        sessionStates = updatedStates
    }
    
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let pollInterval = self.pollInterval
            while !Task.isCancelled {
                await self.refreshAllStatuses()
                try? await Task.sleep(nanoseconds: self.nanoseconds(for: pollInterval))
            }
        }
    }

    private func updateState(
        for command: Command,
        runningSessions: Set<String>,
        generationSnapshot: [String: Int]
    ) async {
        guard !inFlightOperations.contains(command.id) else { return }
        // Ignore stale polling results if a newer operation started after the snapshot.
        let snapshotGeneration = generationSnapshot[command.id] ?? 0
        if operationGenerations[command.id] ?? 0 != snapshotGeneration {
            return
        }
        var state = sessionStates[command.id] ?? SessionState(commandId: command.id)
        let wasRunning = state.isRunning
        let isRunningNow = runningSessions.contains(command.sessionName)

        if isRunningNow {
            state.isRunning = true
            if state.lastStartTime == nil {
                state.lastStartTime = Date()
            }
            // Read from log file for persistent output
            do {
                state.lastOutput = try await TmuxService.readLogFile(
                    path: command.logFilePath,
                    lines: Self.outputLineCount,
                    host: command.host
                )
            } catch {
                // Fallback to tmux capture if log file read fails
                do {
                    state.lastOutput = try await TmuxService.captureOutput(
                        sessionName: command.sessionName,
                        lines: Self.outputLineCount,
                        host: command.host
                    )
                } catch {
                    recordError(error)
                }
            }
        } else {
            state.isRunning = false
            if wasRunning {
                state.lastExitTime = Date()
                // Capture final output from log file before auto-restarting
                do {
                    let finalOutput = try await TmuxService.readLogFile(
                        path: command.logFilePath,
                        lines: Self.outputLineCount,
                        host: command.host
                    )
                    state.lastOutput = finalOutput
                } catch {
                    // Silently ignore log read errors
                }
                await handleAutoRestart(for: command, state: &state)
            }
        }

        sessionStates[command.id] = state
    }

    private func startSessionLocked(commandId: String, command: Command, resetFailureCount: Bool) async throws {
        if await TmuxService.isRunning(command) {
            throw SessionManagerError.sessionAlreadyRunning(commandId)
        }

        do {
            try await TmuxService.startSession(for: command)

            var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
            state.isRunning = true
            state.lastStartTime = Date()
            // Only reset failure counter on manual start, not on auto-restart
            if resetFailureCount {
                state.consecutiveFailures = 0
            }
            state.lastError = nil
            state.lastErrorTime = nil
            state.isConnectionError = nil
            sessionStates[commandId] = state
        } catch {
            var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
            // Try to identify SSH errors and present friendlier messages.
            // Prefer inspecting TmuxError.commandFailed output (if available) to get raw stderr, otherwise fall back to localizedDescription.
            var diagnosticText = error.localizedDescription
            if let tmuxErr = error as? TmuxError {
                switch tmuxErr {
                case .commandFailed(let output, _):
                    diagnosticText = output
                default:
                    break
                }
            }

            if let sshMessage = Shell.parseSSHError(diagnosticText) {
                state.isConnectionError = true
                state.lastError = sshMessage
            } else {
                state.isConnectionError = false
                state.lastError = diagnosticText
            }
            state.lastErrorTime = Date()
            sessionStates[commandId] = state
            await sendStartupFailureNotification(for: command, error: error)
            throw error
        }
    }
    
    private func handleAutoRestart(for command: Command, state: inout SessionState) async {
        guard command.autoRestart.enabled else {
            // Session crashed but auto-restart is disabled
            await sendCrashNotification(for: command)
            return
        }
        guard !state.restartPaused else {
            return
        }

        // If recent connection errors occurred, pause restarts to avoid spamming failures
        if state.isConnectionError == true,
           let lastErrorTime = state.lastErrorTime,
           Date().timeIntervalSince(lastErrorTime) < 60 {
            state.restartPaused = true
            let connectionMessage = state.lastError
            Task { await sendConnectionFailureNotification(for: command, message: connectionMessage) }
            return
        }

        var nextFailures = state.consecutiveFailures

        if let lastStart = state.lastStartTime, let lastExit = state.lastExitTime {
            let runDuration = max(0, lastExit.timeIntervalSince(lastStart))
            if runDuration > Self.failureResetInterval {
                nextFailures = 0
            }
        }

        nextFailures += 1
        state.consecutiveFailures = nextFailures

        if state.consecutiveFailures >= command.autoRestart.maxRetries {
            state.restartPaused = true
            await sendFailureNotification(for: command, failures: state.consecutiveFailures)
            return
        }

        // Send notification for first crash to inform user auto-restart is happening
        if state.consecutiveFailures == 1 {
            await sendCrashNotification(for: command)
        }

        let delaySeconds = max(0, command.autoRestart.retryDelaySeconds)
        let commandId = command.id

        restartTasks[commandId]?.task.cancel()
        let taskId = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let sleepDuration = self.nanoseconds(for: TimeInterval(delaySeconds))
            try? await Task.sleep(nanoseconds: sleepDuration)

            // Clean up any dead session before attempting restart
            if let command = self.command(for: commandId) {
                if await TmuxService.hasSession(name: command.sessionName, host: command.host) {
                    try? await TmuxService.killSession(name: command.sessionName, host: command.host)
                }
            }

            do {
                try await self.startSession(commandId: commandId, resetFailureCount: false)
            } catch {
                self.recordError(error)
                // Update failure state to prevent infinite restart attempts
                var state = self.sessionStates[commandId] ?? SessionState(commandId: commandId)
                state.lastError = error.localizedDescription
                state.lastErrorTime = Date()
                self.sessionStates[commandId] = state
            }
            self.clearRestartTask(commandId: commandId, taskId: taskId)
        }
        restartTasks[commandId] = RestartTask(id: taskId, task: task)
    }
    
    private func sendFailureNotification(for command: Command, failures: Int) async {
        let isAuthorized = await requestNotificationAuthorization()
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "bgcli: Session Failed"
        content.body = "\(command.name) has failed \(failures) times and auto-restart has been paused."

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            recordError(error)
        }
    }

    private func sendConnectionFailureNotification(for command: Command, message: String?) async {
        let isAuthorized = await requestNotificationAuthorization()
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "bgcli: SSH Connection Error"
        if let message = message {
            content.body = "\(command.name): \(message). Auto-restart paused."
        } else {
            content.body = "\(command.name): SSH connection failed. Auto-restart paused."
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            recordError(error)
        }
    }

    private func sendStartupFailureNotification(for command: Command, error: Error) async {
        let isAuthorized = await requestNotificationAuthorization()
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "bgcli: Failed to Start"
        content.body = "\(command.name) failed to start: \(error.localizedDescription)"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            recordError(error)
        }
    }

    private func sendCrashNotification(for command: Command) async {
        let isAuthorized = await requestNotificationAuthorization()
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "bgcli: Session Crashed"
        let body: String
        if command.autoRestart.enabled {
            body = "\(command.name) has stopped unexpectedly. Auto-restarting in \(command.autoRestart.retryDelaySeconds)s..."
        } else {
            body = "\(command.name) has stopped unexpectedly."
        }
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            recordError(error)
        }
    }
    
    private func requestNotificationAuthorization() async -> Bool {
        let status = await notificationAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            break
        @unknown default:
            return false
        }
        
        guard !hasRequestedNotificationPermission else { return false }
        hasRequestedNotificationPermission = true
        
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            ) { granted, error in
                if let error = error {
                    Task { @MainActor [weak self] in
                        self?.recordError(error)
                    }
                } else if !granted {
                    Task { @MainActor [weak self] in
                        self?.recordError(SessionManagerError.notificationDenied)
                    }
                }
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func recordError(_ error: Error) {
        lastError = error.localizedDescription
    }

    private func checkTmuxInstalled() async {
        // Try which first (will now use augmented PATH)
        if await Shell.runQuiet("which tmux") {
            isTmuxInstalled = true
            return
        }

        // Fallback: check common installation paths directly
        let commonPaths = [
            "/opt/homebrew/bin/tmux",  // Apple Silicon Homebrew
            "/usr/local/bin/tmux",     // Intel Mac Homebrew
            "/usr/bin/tmux"            // System installation
        ]

        for path in commonPaths {
            if await Shell.runQuiet("test -x '\(path)'") {
                isTmuxInstalled = true
                print("[SessionManager] Found tmux at: \(path)")
                return
            }
        }

        isTmuxInstalled = false
    }

    func testConnection(host: String?) async -> Bool {
        return await Shell.runQuiet("true", host: host)
    }

    private func handleConfigError(_ error: ConfigError) async {
        let alert = NSAlert()
        alert.messageText = "Configuration Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Open Config File")
        alert.addButton(withTitle: "Reset to Default")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(AppConfig.configFilePath)
        case .alertSecondButtonReturn:
            await resetConfig()
        default:
            NSApplication.shared.terminate(nil)
        }
    }

    private func resetConfig() async {
        // Backup corrupted config
        let backupPath = AppConfig.configDirectory
            .appendingPathComponent("config.json.backup.\(Date().timeIntervalSince1970)")
        try? FileManager.default.copyItem(
            at: AppConfig.configFilePath,
            to: backupPath
        )

        // Create fresh config
        let defaultConfig = AppConfig.createDefaultConfig()
        try? defaultConfig.save()
        try? await loadConfig()
    }
    
    private func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        let clamped = max(0, seconds)
        let maxSeconds = TimeInterval(UInt64.max) / TimeInterval(Self.nanosecondsPerSecond)
        let safeSeconds = min(clamped, maxSeconds)
        return UInt64(safeSeconds * TimeInterval(Self.nanosecondsPerSecond))
    }
    
    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
    
    private func clearRestartTask(commandId: String, taskId: UUID) {
        if restartTasks[commandId]?.id == taskId {
            restartTasks[commandId] = nil
        }
    }

    private func commandLock(for commandId: String) -> CommandLock {
        if let existingLock = commandLocks[commandId] {
            return existingLock
        }
        let lock = CommandLock()
        commandLocks[commandId] = lock
        return lock
    }

    private func withCommandLock<T>(
        commandId: String,
        operation: () async throws -> T
    ) async throws -> T {
        let lock = commandLock(for: commandId)
        await lock.lock()
        inFlightOperations.insert(commandId)
        operationGenerations[commandId, default: 0] += 1

        do {
            let result = try await operation()
            inFlightOperations.remove(commandId)
            await lock.unlock()
            return result
        } catch {
            inFlightOperations.remove(commandId)
            await lock.unlock()
            throw error
        }
    }
}
