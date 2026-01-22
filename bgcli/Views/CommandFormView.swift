//
//  CommandFormView.swift
//  bgcli
//
//  Created for bgcli project
//

import SwiftUI

struct CommandFormView: View {
    enum Mode {
        case add
        case edit(Command)

        var title: String {
            switch self {
            case .add: return "Add Command"
            case .edit: return "Edit Command"
            }
        }

        var saveButtonTitle: String {
            switch self {
            case .add: return "Add"
            case .edit: return "Save"
            }
        }
    }

    let mode: Mode

    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    // Form fields
    @State private var name: String = ""
    @State private var command: String = ""
    @State private var workingDirectory: String = ""
    @State private var host: String = ""
    @State private var autoRestartEnabled: Bool = true
    @State private var maxRetries: Int = 3
    @State private var retryDelaySeconds: Int = 3
    @State private var environmentVariables: [EnvironmentVariable] = []

    // UI state
    @State private var showingValidationError: Bool = false
    @State private var validationErrorMessage: String = ""
    @State private var showingRunningCommandWarning: Bool = false
    @State private var pendingSave: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name, prompt: Text("My Background Service"))
                    TextField("Command", text: $command, prompt: Text("npm start"), axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Execution Options") {
                    TextField("Working Directory (optional)", text: $workingDirectory, prompt: Text("/path/to/project"))
                    TextField("SSH Host (optional)", text: $host, prompt: Text("user@host.com"))
                        .help("Leave empty for local execution")
                }

                Section {
                    Toggle("Enable Auto Restart", isOn: $autoRestartEnabled)

                    if autoRestartEnabled {
                        Stepper("Max Retries: \(maxRetries)", value: $maxRetries, in: 1...100)
                        Stepper("Retry Delay: \(retryDelaySeconds)s", value: $retryDelaySeconds, in: 1...300)
                    }
                } header: {
                    Text("Auto Restart")
                } footer: {
                    Text("Automatically restart the command if it exits unexpectedly")
                }

                Section {
                    ForEach($environmentVariables) { $envVar in
                        HStack {
                            TextField("KEY", text: $envVar.key)
                                .frame(maxWidth: 200)
                            TextField("value", text: $envVar.value)
                            Button {
                                environmentVariables.removeAll { $0.id == envVar.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        environmentVariables.append(EnvironmentVariable(key: "", value: ""))
                    } label: {
                        Label("Add Variable", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Environment Variables")
                } footer: {
                    Text("Custom environment variables for this command")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveButtonTitle) {
                        saveCommand()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .alert("Validation Error", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationErrorMessage)
            }
            .alert("Command is Running", isPresented: $showingRunningCommandWarning) {
                Button("Cancel", role: .cancel) {
                    pendingSave = nil
                }
                Button("Save Without Restarting") {
                    pendingSave?()
                    pendingSave = nil
                }
                Button("Save and Restart") {
                    if let save = pendingSave {
                        save()
                        if case .edit(let originalCommand) = mode {
                            Task {
                                try? await sessionManager.restartSession(commandId: originalCommand.id)
                            }
                        }
                    }
                    pendingSave = nil
                }
            } message: {
                Text("This command is currently running. Changes will take effect on the next restart. Would you like to restart it now?")
            }
            .onAppear {
                loadFormData()
            }
        }
    }

    private func loadFormData() {
        guard case .edit(let existingCommand) = mode else { return }

        name = existingCommand.name
        command = existingCommand.command
        workingDirectory = existingCommand.workingDirectory ?? ""
        host = existingCommand.host ?? ""
        autoRestartEnabled = existingCommand.autoRestart.enabled
        maxRetries = existingCommand.autoRestart.maxRetries
        retryDelaySeconds = existingCommand.autoRestart.retryDelaySeconds

        environmentVariables = existingCommand.env.map { key, value in
            EnvironmentVariable(key: key, value: value)
        }.sorted { $0.key < $1.key }
    }

    private func saveCommand() {
        // Validate
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationErrorMessage = "Command name cannot be empty"
            showingValidationError = true
            return
        }

        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationErrorMessage = "Command cannot be empty"
            showingValidationError = true
            return
        }

        // Check if command is running (for edit mode)
        if case .edit(let originalCommand) = mode {
            if let state = sessionManager.sessionStates[originalCommand.id], state.isRunning {
                pendingSave = performSave
                showingRunningCommandWarning = true
                return
            }
        }

        performSave()
    }

    private func performSave() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkingDir = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build env dictionary, filtering out empty keys
        let envDict = Dictionary(
            uniqueKeysWithValues: environmentVariables
                .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { ($0.key.trimmingCharacters(in: .whitespacesAndNewlines),
                        $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )

        let autoRestartConfig = Command.AutoRestartConfig(
            enabled: autoRestartEnabled,
            maxRetries: maxRetries,
            retryDelaySeconds: retryDelaySeconds
        )

        Task {
            switch mode {
            case .add:
                let newCommand = Command(
                    id: UUID().uuidString,
                    name: trimmedName,
                    command: trimmedCommand,
                    workingDirectory: trimmedWorkingDir.isEmpty ? nil : trimmedWorkingDir,
                    host: trimmedHost.isEmpty ? nil : trimmedHost,
                    autoRestart: autoRestartConfig,
                    env: envDict
                )
                try? await sessionManager.addCommand(newCommand)

            case .edit(let originalCommand):
                let updatedCommand = Command(
                    id: originalCommand.id,
                    name: trimmedName,
                    command: trimmedCommand,
                    workingDirectory: trimmedWorkingDir.isEmpty ? nil : trimmedWorkingDir,
                    host: trimmedHost.isEmpty ? nil : trimmedHost,
                    autoRestart: autoRestartConfig,
                    env: envDict
                )
                try? await sessionManager.updateCommand(updatedCommand)
            }

            dismiss()
        }
    }
}

struct EnvironmentVariable: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

#Preview("Add Mode") {
    CommandFormView(mode: .add)
        .environmentObject(SessionManager())
}

#Preview("Edit Mode") {
    CommandFormView(mode: .edit(Command(
        id: "test-id",
        name: "Test Server",
        command: "npm start",
        workingDirectory: "/path/to/project",
        host: nil,
        autoRestart: Command.AutoRestartConfig(enabled: true, maxRetries: 5, retryDelaySeconds: 5),
        env: ["NODE_ENV": "development"]
    )))
    .environmentObject(SessionManager())
}
