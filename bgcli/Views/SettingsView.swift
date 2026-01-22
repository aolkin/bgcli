//
//  SettingsView.swift
//  bgcli
//
//  Created for bgcli project
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var selectedCommandId: String?
    @State private var isAddingCommand = false
    @State private var editingCommand: Command?

    var body: some View {
        NavigationSplitView {
            // Command List Sidebar
            VStack(spacing: 0) {
                List(selection: $selectedCommandId) {
                    ForEach(sessionManager.commands) { command in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(command.name)
                                    .font(.headline)
                                Text(command.command)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if let state = sessionManager.sessionStates[command.id], state.isRunning {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(.green)
                                    .imageScale(.small)
                            }
                        }
                        .tag(command.id)
                        .contextMenu {
                            Button("Edit") {
                                editingCommand = command
                            }

                            Button("Duplicate") {
                                duplicateCommand(command)
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                deleteCommand(command)
                            }
                        }
                    }
                }

                Divider()

                // Add Command button at bottom of sidebar
                HStack {
                    Button {
                        isAddingCommand = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("Commands")
        } detail: {
            if let commandId = selectedCommandId,
               let command = sessionManager.commands.first(where: { $0.id == commandId }) {
                CommandDetailView(command: command, onEdit: {
                    editingCommand = command
                })
            } else {
                VStack {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Command Selected")
                        .font(.headline)
                        .padding(.top)
                    Text("Select a command from the list or add a new one")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $isAddingCommand) {
            CommandFormView(mode: .add)
        }
        .sheet(item: $editingCommand) { command in
            CommandFormView(mode: .edit(command))
        }
    }

    private func duplicateCommand(_ command: Command) {
        let newCommand = Command(
            id: UUID().uuidString,
            name: command.name + " (Copy)",
            command: command.command,
            workingDirectory: command.workingDirectory,
            host: command.host,
            autoRestart: command.autoRestart,
            env: command.env
        )
        Task {
            try? await sessionManager.addCommand(newCommand)
        }
    }

    private func deleteCommand(_ command: Command) {
        Task {
            try? await sessionManager.removeCommand(id: command.id)
        }
    }
}

struct CommandDetailView: View {
    let command: Command
    let onEdit: () -> Void

    @EnvironmentObject private var sessionManager: SessionManager

    private var sessionState: SessionState? {
        sessionManager.sessionStates[command.id]
    }

    var body: some View {
        Form {
            Section("Basic Information") {
                LabeledContent("Name", value: command.name)
                LabeledContent("Command") {
                    Text(command.command)
                        .textSelection(.enabled)
                }
            }

            Section("Configuration") {
                if let workingDir = command.workingDirectory {
                    LabeledContent("Working Directory", value: workingDir)
                }

                if let host = command.host {
                    LabeledContent("SSH Host", value: host)
                }
            }

            Section("Auto Restart") {
                LabeledContent("Enabled", value: command.autoRestart.enabled ? "Yes" : "No")
                if command.autoRestart.enabled {
                    LabeledContent("Max Retries", value: "\(command.autoRestart.maxRetries)")
                    LabeledContent("Retry Delay", value: "\(command.autoRestart.retryDelaySeconds)s")
                }
            }

            if !command.env.isEmpty {
                Section("Environment Variables") {
                    ForEach(command.env.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                    }
                }
            }

            if let state = sessionState {
                Section("Status") {
                    LabeledContent("State") {
                        HStack {
                            if state.isRunning {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(.green)
                                Text("Running")
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                                Text("Stopped")
                            }
                        }
                    }

                    if state.restartPaused {
                        LabeledContent("Auto Restart", value: "Paused (max retries)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    onEdit()
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SessionManager())
}
