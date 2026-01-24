//
//  MenuContentView.swift
//  bgcli
//
//  Created for bgcli project
//

import SwiftUI
import AppKit

struct MenuContentView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.openWindow) private var openWindow

    private func openAndActivateSettings() {
        openWindow(id: "settings")
        // Bring the window to front after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            // Find and bring settings window to front
            for window in NSApp.windows {
                if window.title == "Settings" {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
    }

    var body: some View {
        Group {
            if !sessionManager.isTmuxInstalled {
                Section {
                    Label("tmux not installed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("How to Install") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/tmux/tmux/wiki/Installing")!)
                    }
                }
                Divider()
            }

            if sessionManager.commandsWithState.isEmpty {
                // Auto-open settings when no commands exist
                Color.clear
                    .onAppear {
                        openAndActivateSettings()
                    }

                Button("No commands configured") {}
                    .disabled(true)

                Button("Open Config File") {
                    NSWorkspace.shared.open(AppConfig.configFilePath)
                }
            } else {
                Section("Commands") {
                    ForEach(sessionManager.commandsWithState) { entry in
                        CommandMenuSection(command: entry.command, state: entry.state)
                    }
                }
            }

            Divider()

            Button("Settings...") {
                openAndActivateSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit bgcli") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

#Preview {
    MenuContentView()
        .environmentObject(SessionManager())
}
