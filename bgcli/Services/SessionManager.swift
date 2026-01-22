//
//  SessionManager.swift
//  bgcli
//
//  Created for bgcli project
//

import Foundation
import UserNotifications

enum SessionManagerError: Error, LocalizedError {
    case commandNotFound(String)
    case sessionAlreadyRunning(String)
    
    var errorDescription: String? {
        switch self {
        case .commandNotFound(let id):
            return "Command with ID '\(id)' was not found"
        case .sessionAlreadyRunning(let id):
            return "Session for command '\(id)' is already running"
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
    
    @Published private(set) var commands: [Command] = []
    @Published private(set) var sessionStates: [String: SessionState] = [:]
    @Published var isLoading = false
    @Published var lastError: String?
    
    private static let outputLineCount = 10
    private static let failureResetInterval: TimeInterval = 30
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    
    private let pollInterval: TimeInterval
    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var restartTasks: [String: RestartTask] = [:]
    private var isRefreshing = false
    private var hasRequestedNotificationPermission = false
    
    init(pollInterval: TimeInterval = 3.0) {
        self.pollInterval = pollInterval
        
        loadTask = Task { [weak self] in
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
    
    func startSession(commandId: String) async throws {
        guard let command = command(for: commandId) else {
            throw SessionManagerError.commandNotFound(commandId)
        }
        
        if await TmuxService.isRunning(command) {
            throw SessionManagerError.sessionAlreadyRunning(commandId)
        }
        
        try await TmuxService.startSession(for: command)
        
        var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
        state.isRunning = true
        state.lastStartTime = Date()
        state.consecutiveFailures = 0
        sessionStates[commandId] = state
    }
    
    func stopSession(commandId: String) async throws {
        guard let command = command(for: commandId) else {
            throw SessionManagerError.commandNotFound(commandId)
        }
        
        try await TmuxService.killSession(name: command.sessionName, host: command.host)
        
        var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
        state.isRunning = false
        state.lastExitTime = Date()
        state.restartPaused = true
        sessionStates[commandId] = state
    }
    
    func restartSession(commandId: String) async throws {
        guard let command = command(for: commandId) else {
            throw SessionManagerError.commandNotFound(commandId)
        }
        
        if await TmuxService.isRunning(command) {
            try await TmuxService.killSession(name: command.sessionName, host: command.host)
        }
        
        var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
        state.restartPaused = false
        sessionStates[commandId] = state
        
        try await startSession(commandId: commandId)
    }
    
    func resumeAutoRestart(commandId: String) async throws {
        var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
        state.restartPaused = false
        state.consecutiveFailures = 0
        sessionStates[commandId] = state
        
        try await startSession(commandId: commandId)
    }
    
    func refreshAllStatuses() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let groupedCommands = Dictionary(grouping: commands, by: { $0.host })
        
        for (host, hostCommands) in groupedCommands {
            do {
                let sessions = try await TmuxService.listSessions(host: host)
                let runningSessions = Set(sessions.map { $0.name })
                
                for command in hostCommands {
                    await updateState(for: command, runningSessions: runningSessions)
                }
            } catch {
                recordError(error)
            }
        }
    }
    
    func refreshStatus(commandId: String) async {
        guard let command = command(for: commandId) else { return }
        
        do {
            let sessions = try await TmuxService.listSessions(host: command.host)
            let runningSessions = Set(sessions.map { $0.name })
            
            await updateState(for: command, runningSessions: runningSessions)
        } catch {
            recordError(error)
        }
    }
    
    func getOutput(commandId: String, lines: Int = SessionManager.outputLineCount) async throws -> [String] {
        guard let command = command(for: commandId) else {
            throw SessionManagerError.commandNotFound(commandId)
        }
        
        let output = try await TmuxService.captureOutput(
            sessionName: command.sessionName,
            lines: lines,
            host: command.host
        )
        
        var state = sessionStates[commandId] ?? SessionState(commandId: commandId)
        state.lastOutput = output
        sessionStates[commandId] = state
        
        return output
    }
    
    private func loadInitialConfig() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await loadConfig()
            startPolling()
            await refreshAllStatuses()
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
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAllStatuses()
                try? await Task.sleep(nanoseconds: self.nanoseconds(for: self.pollInterval))
            }
        }
    }

    private func updateState(for command: Command, runningSessions: Set<String>) async {
        var state = sessionStates[command.id] ?? SessionState(commandId: command.id)
        let wasRunning = state.isRunning
        let isRunningNow = runningSessions.contains(command.sessionName)
        
        if isRunningNow {
            state.isRunning = true
            if state.lastStartTime == nil {
                state.lastStartTime = Date()
            }
            do {
                state.lastOutput = try await TmuxService.captureOutput(
                    sessionName: command.sessionName,
                    lines: Self.outputLineCount,
                    host: command.host
                )
            } catch {
                recordError(error)
            }
        } else {
            state.isRunning = false
            if wasRunning {
                state.lastExitTime = Date()
                await handleAutoRestart(for: command, state: &state)
            }
        }
        
        sessionStates[command.id] = state
    }
    
    private func handleAutoRestart(for command: Command, state: inout SessionState) async {
        guard command.autoRestart.enabled else { return }
        guard !state.restartPaused else { return }
        
        var nextFailures = state.consecutiveFailures
        
        if let lastStart = state.lastStartTime, let lastExit = state.lastExitTime {
            if lastStart.distance(to: lastExit) > Self.failureResetInterval {
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
        
        let delaySeconds = max(0, command.autoRestart.retryDelaySeconds)
        let commandId = command.id
        
        restartTasks[commandId]?.task.cancel()
        let taskId = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.nanoseconds(for: TimeInterval(delaySeconds)))
            do {
                try await self.startSession(commandId: commandId)
            } catch {
                self.recordError(error)
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
        
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
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
            ) { [weak self] granted, error in
                if let error {
                    self?.recordError(error)
                }
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func recordError(_ error: Error) {
        lastError = error.localizedDescription
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
}
