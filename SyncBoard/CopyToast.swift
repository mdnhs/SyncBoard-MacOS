//
//  CopyToast.swift
//  SyncBoard
//

import UserNotifications

/// Shows a native macOS notification banner whenever something is copied
/// from SyncBoard, so copying from the popover or main window gives the
/// same confirmation a normal ⌘C does.
@MainActor
enum CopyToast {
    private static let maxPreviewLength = 80

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func show(for text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Copied to Clipboard"
        content.body = preview(of: text)

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func preview(of text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxPreviewLength else { return collapsed }
        return String(collapsed.prefix(maxPreviewLength)) + "…"
    }
}
