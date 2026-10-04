//
//  SyncBoardApp.swift
//  SyncBoard
//

import SwiftUI

@main
struct SyncBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(ClipboardManager.shared)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(ClipboardManager.shared)
        }
        .windowResizability(.contentMinSize)
        #endif
    }
}
