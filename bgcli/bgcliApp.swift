//
//  bgcliApp.swift
//  bgcli
//
//  Created for bgcli project
//

import SwiftUI

@main
struct bgcliApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        MenuBarExtra("bgcli", systemImage: "terminal") {
            MenuContentView()
                .environmentObject(sessionManager)
        }
        .menuBarExtraStyle(.menu)
    }
}
