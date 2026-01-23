//
//  CommandMenuSection.swift
//  bgcli
//
//  Created for bgcli project
//

import AppKit
import SwiftUI

struct CommandMenuSection: View {
    @EnvironmentObject private var sessionManager: SessionManager

    let command: Command
    let state: SessionState

    private static let outputPreviewLineCount = 10
    private static let outputPreviewLineLength = 60
    private static let outputPreviewEllipsis = "..."

    var body: some View {
        Menu {
            commandStateActions

            Button("Copy Output") {
                copyOutputToPasteboard()
            }
            .disabled(state.lastOutput.isEmpty)

            Button("View Full Log") {
                viewFullLog()
            }

            Divider()

            outputPreviewSection

            if let error = state.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    if let errorTime = state.lastErrorTime {
                        Text(errorTime, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if state.consecutiveFailures > 0 {
                Section {
                    if state.restartPaused {
                        Label("Auto-restart paused after \(state.consecutiveFailures) failures", systemImage: "pause.circle")
                            .foregroundStyle(.yellow)
                    } else {
                        Label("Failures: \(state.consecutiveFailures) / \(command.autoRestart.maxRetries)", systemImage: "arrow.clockwise")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        } label: {
            Label(commandLabel, systemImage: state.statusIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
        }
    }

    private var outputPreviewSection: some View {
        Section {
            if outputPreviewLines.isEmpty {
                Text("No output yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(outputPreviewLines.enumerated()), id: \.offset) { _, line in
                    Text(truncatedOutputLine(line))
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private var commandStateActions: some View {
        Group {
            if state.restartPaused {
                Button("Resume & Start") {
                    Task { @MainActor in
                        await handleAction { try await sessionManager.resumeAutoRestart(commandId: command.id) }
                    }
                }
            } else if state.isRunning {
                Button("Stop") {
                    Task { @MainActor in
                        await handleAction { try await sessionManager.stopSession(commandId: command.id) }
                    }
                }

                Button("Restart") {
                    Task { @MainActor in
                        await handleAction { try await sessionManager.restartSession(commandId: command.id) }
                    }
                }

                Button("Open in Terminal") {
                    Task { @MainActor in
                        await handleAction {
                            try await TerminalLauncher.openSession(
                                sessionName: command.sessionName,
                                host: command.host
                            )
                        }
                    }
                }
            } else {
                Button("Start") {
                    Task { @MainActor in
                        await handleAction { try await sessionManager.startSession(commandId: command.id) }
                    }
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

    private var outputPreviewLines: [String] {
        Array(state.lastOutput.suffix(Self.outputPreviewLineCount))
    }

    private func truncatedOutputLine(_ line: String) -> String {
        guard line.count > Self.outputPreviewLineLength else {
            return line
        }
        let prefix = line.prefix(Self.outputPreviewLineLength)
        return String(prefix) + Self.outputPreviewEllipsis
    }

    @MainActor
    private func handleAction(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
        } catch {
            sessionManager.lastError = error.localizedDescription
        }
    }

    private func copyOutputToPasteboard() {
        guard !state.lastOutput.isEmpty else { return }
        let text = state.lastOutput.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setString(text, forType: .string) {
            sessionManager.lastError = "Unable to copy command output to clipboard. Please try again."
        }
    }

    private func viewFullLog() {
        let logFileURL = URL(fileURLWithPath: command.logFilePath)

        // Ensure the log file exists, create empty if it doesn't
        if !FileManager.default.fileExists(atPath: command.logFilePath) {
            FileManager.default.createFile(atPath: command.logFilePath, contents: Data("Log file created.\n".utf8))
        }

        // Open the log file in the default text editor
        NSWorkspace.shared.open(logFileURL)
    }
}

#Preview {
    CommandMenuSection(
        command: Command(id: "demo", name: "Demo", command: "echo hello", host: "remote"),
        state: SessionState(commandId: "demo", isRunning: true)
    )
    .environmentObject(SessionManager())
}
