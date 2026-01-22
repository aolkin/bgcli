//
//  MenuContentView.swift
//  bgcli
//
//  Created for bgcli project
//

import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.openWindow) private var openWindow

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
                        openWindow(id: "settings")
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
                openWindow(id: "settings")
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
