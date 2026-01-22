//
//  bgcliApp.swift
//  bgcli
//
//  Created for bgcli project
//

import SwiftUI

@main
struct bgcliApp: App {
    var body: some Scene {
        MenuBarExtra("bgcli", systemImage: "terminal") {
            Text("bgcli")
                .font(.headline)
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
