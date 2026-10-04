//
//  AppDelegate.swift
//  SyncBoard
//

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UserNotifications

/// Owns the menu bar icon and its quick-access popover. The main app window
/// (opened via the Dock icon) is managed entirely by SwiftUI's WindowGroup and
/// is intentionally not touched here.
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyTheme()
        ClipboardManager.shared.startMonitoring()
        UNUserNotificationCenter.current().delegate = self
        CopyToast.requestAuthorizationIfNeeded()
        GoogleDriveSyncManager.shared.startPeriodicSync()
        setupStatusItem()
        setupPopover()
        setupHotKey()

        AppSettings.shared.onThemeChange = { [weak self] _ in
            self?.updatePopoverAppearance()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if AppSettings.shared.clearHistoryOnQuit {
            ClipboardManager.shared.clearAll()
        }
    }

    /// Without this, macOS suppresses the copy-confirmation banner while
    /// SyncBoard itself is the frontmost app (which it always is right
    /// after a copy, since the user just clicked something in its popover).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        // Template mode lets the menu bar tint the icon for light/dark and
        // highlighted states instead of drawing it with fixed colors.
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        item.button?.image = icon
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item
    }

    private func setupPopover() {
        popover.delegate = self
        popover.behavior = .transient
        updatePopoverAppearance()

        let hostingController = NSHostingController(
            rootView: MenuBarPopoverView()
                .environment(ClipboardManager.shared)
                .environment(\.dismissPopover, { [weak self] in self?.popover.performClose(nil) })
        )
        // The popover's contentSize is set explicitly in updatePopoverSize(for:), so the
        // hosting controller must not derive its own size constraints from the SwiftUI
        // content's ideal size. Left at the default (.standardBounds), the ScrollView's
        // ideal height (= the full, unclipped content height) fights that fixed size and
        // the scrollable area ends up clamped short, making the list appear to get stuck
        // partway through instead of scrolling all the way.
        hostingController.sizingOptions = []
        popover.contentViewController = hostingController
    }

    private func updatePopoverAppearance() {
        let appearance = AppSettings.shared.appearanceTheme.nsAppearance
        popover.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
        if let window = popover.contentViewController?.view.window {
            window.appearance = appearance
        }
    }

    /// Sizes the popover to 72% of the status item's current screen height,
    /// re-derived on every open since it can move between displays.
    private func updatePopoverSize(for button: NSStatusBarButton) {
        let screenHeight = (button.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 600
        popover.contentSize = NSSize(width: 360, height: screenHeight * 0.72)
    }

    private func setupHotKey() {
        HotKeyManager.shared.onHotKeyPressed = { [weak self] in
            self?.togglePopover()
        }
        HotKeyManager.shared.applyCurrentPreset()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopoverSize(for: button)
            updatePopoverAppearance()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            configurePopoverWindow()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        configurePopoverWindow()
    }

    private func configurePopoverWindow() {
        updatePopoverAppearance()
        if let window = popover.contentViewController?.view.window {
            window.allowsToolTipsWhenApplicationIsInactive = true
            window.makeKey()
        }
    }
}
