//
//  Color+Theme.swift
//  SyncBoard
//

import SwiftUI
import AppKit

extension Color {
    /// The popover/window page background. Uses the requested #f4f4f4 in
    /// light mode; falls back to a comparable dark surface in dark mode so
    /// the app still follows the system appearance overall.
    static let primaryBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(white: 0.11, alpha: 1)
            : NSColor(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF4 / 255, alpha: 1)
    })
}
