//
//  daemonicApp.swift
//  daemonic
//
//  Created for daemonic project
//

import SwiftUI

@main
struct daemonicApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        MenuBarExtra("Daemonic", systemImage: "terminal") {
            MenuContentView()
                .environmentObject(sessionManager)
        }
        .menuBarExtraStyle(.menu)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(sessionManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
    }
}
