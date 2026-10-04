//
//  CopyToast.swift
//  SyncBoard
//

import AppKit
import UserNotifications

/// Shows a native macOS notification banner and/or plays audio feedback
/// whenever something is copied from SyncBoard, according to user preferences.
@MainActor
enum CopyToast {
    private static let maxPreviewLength = 80

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func show(for text: String, isSensitive: Bool) {
        if AppSettings.shared.playSoundOnCopy {
            NSSound(named: "Tink")?.play()
        }

        guard AppSettings.shared.showNotificationsOnCopy else { return }

        let content = UNMutableNotificationContent()
        content.title = "Copied to Clipboard"
        // Never surface the real value in a system banner for sensitive
        // content — notifications can linger on-screen and in Notification
        // Center well after the clipboard itself has moved on.
        content.body = isSensitive ? "Sensitive content copied" : preview(of: text)

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func preview(of text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxPreviewLength else { return collapsed }
        return String(collapsed.prefix(maxPreviewLength)) + "…"
    }
}
