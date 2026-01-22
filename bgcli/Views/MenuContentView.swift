//
//  MenuContentView.swift
//  bgcli
//
//  Created for bgcli project
//

import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        if sessionManager.commandsWithState.isEmpty {
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

        Button("Settings...") {}
            .disabled(true)

        Divider()

        Button("Quit bgcli") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

#Preview {
    MenuContentView()
        .environmentObject(SessionManager())
}
