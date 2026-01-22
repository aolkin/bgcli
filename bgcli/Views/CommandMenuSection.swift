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
            outputPreviewSection

            Divider()

            Button("Copy Output") {
                copyOutputToPasteboard()
            }
            .disabled(state.lastOutput.isEmpty)

            commandStateActions
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
                    .foregroundColor(.secondary)
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

    private var outputPreviewLines: [String] {
        Array(state.lastOutput.suffix(Self.outputPreviewLineCount))
    }

    private func truncatedOutputLine(_ line: String) -> String {
        guard line.count > Self.outputPreviewLineLength else {
            return line
        }
        let prefix = line.prefix(Self.outputPreviewLineLength)
        return "\(prefix)\(Self.outputPreviewEllipsis)"
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
        let text = state.lastOutput.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setString(text, forType: .string) {
            sessionManager.lastError = "Unable to copy output to clipboard."
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
