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
        .commands {
            // ⌘, opens the same settings window as the in-app buttons, instead of a second Settings scene.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppSettings.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
