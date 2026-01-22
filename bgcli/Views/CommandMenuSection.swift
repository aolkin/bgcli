//
//  CommandMenuSection.swift
//  bgcli
//
//  Created for bgcli project
//

import SwiftUI

struct CommandMenuSection: View {
    @EnvironmentObject private var sessionManager: SessionManager

    let command: Command
    let state: SessionState

    var body: some View {
        Menu {
            commandStateActions

            Divider()

            Button("View Output") {
            }
            .disabled(true)
            .help("Output preview not available yet")
        } label: {
            Label(commandLabel, systemImage: state.statusIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
        }
    }

    private var commandStateActions: some View {
        Group {
            if state.restartPaused {
                Button("Resume & Start") {
                    Task { await handleAction { try await sessionManager.resumeAutoRestart(commandId: command.id) } }
                }
            } else if state.isRunning {
                Button("Stop") {
                    Task { await handleAction { try await sessionManager.stopSession(commandId: command.id) } }
                }

                Button("Restart") {
                    Task { await handleAction { try await sessionManager.restartSession(commandId: command.id) } }
                }

                Button("Open in Terminal") {
                }
                .disabled(true)
                .help("Terminal integration not available yet")
            } else {
                Button("Start") {
                    Task { await handleAction { try await sessionManager.startSession(commandId: command.id) } }
                }
            }
        }
    }

    private var commandLabel: String {
        command.isRemote ? "\(command.name) (remote)" : command.name
    }

    private var statusColor: Color {
        if state.restartPaused {
            return .yellow
        }
        if state.isRunning {
            return .green
        }
        return .secondary
    }

    @MainActor
    private func handleAction(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
        } catch {
            sessionManager.lastError = error.localizedDescription
        }
    }
}

#Preview {
    CommandMenuSection(
        command: Command(id: "demo", name: "Demo", command: "echo hello", host: "remote"),
        state: SessionState(commandId: "demo", isRunning: true)
    )
    .environmentObject(SessionManager())
}
