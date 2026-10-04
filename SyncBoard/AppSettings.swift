//
//  AppSettings.swift
//  SyncBoard
//

import SwiftUI
import Combine
import ServiceManagement
import AppKit
import Carbon

@Observable
public final class AppSettings {
    public static let shared = AppSettings()

    // MARK: - Storage Keys
    private let keyLaunchAtLogin = "SB_LaunchAtLogin"
    private let keyShowNotificationOnCopy = "SB_ShowNotificationOnCopy"
    private let keyPlaySoundOnCopy = "SB_PlaySoundOnCopy"
    private let keyMaxHistoryCount = "SB_MaxHistoryCount"
    private let keyRetentionDays = "SB_RetentionDays"
    private let keyMaskSensitive = "SB_MaskSensitive"
    private let keySyncSensitive = "SB_SyncSensitive"
    private let keyClearOnQuit = "SB_ClearOnQuit"
    private let keyIgnoreConcealed = "SB_IgnoreConcealed"
    private let keyHotKeyPreset = "SB_HotKeyPreset"
    private let keyEnableNumberShortcuts = "SB_EnableNumberShortcuts"
    private let keyExcludedApps = "SB_ExcludedApps"
    private let keyExcludedDomains = "SB_ExcludedDomains"
    private let keySyncInterval = "SB_SyncInterval"
    private let keyTheme = "SB_Theme"

    private let defaults = UserDefaults.standard
    private var isInitialized = false

    // MARK: - Enums
    public enum AppTheme: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        public var id: String { rawValue }

        public var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }

        public var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    public enum HotKeyPreset: String, CaseIterable, Identifiable {
        case cmdShiftV = "⌘ ⇧ V"
        case cmdOptV = "⌘ ⌥ V"
        case ctrlOptV = "⌃ ⌥ V"
        case cmdShiftC = "⌘ ⇧ C"

        public var id: String { rawValue }

        public var keyCode: UInt32 {
            switch self {
            case .cmdShiftV, .cmdOptV, .ctrlOptV:
                return 9 // 'v'
            case .cmdShiftC:
                return 8 // 'c'
            }
        }

        public var modifiers: UInt32 {
            switch self {
            case .cmdShiftV:
                return UInt32(cmdKey | shiftKey)
            case .cmdOptV:
                return UInt32(cmdKey | optionKey)
            case .ctrlOptV:
                return UInt32(controlKey | optionKey)
            case .cmdShiftC:
                return UInt32(cmdKey | shiftKey)
            }
        }
    }

    // MARK: - Properties
    public var launchAtLogin: Bool = false {
        didSet {
            defaults.set(launchAtLogin, forKey: keyLaunchAtLogin)
            if isInitialized {
                updateLaunchAtLoginState(launchAtLogin)
            }
        }
    }

    public var showNotificationsOnCopy: Bool = true {
        didSet { defaults.set(showNotificationsOnCopy, forKey: keyShowNotificationOnCopy) }
    }

    public var playSoundOnCopy: Bool = true {
        didSet { defaults.set(playSoundOnCopy, forKey: keyPlaySoundOnCopy) }
    }

    public var maxHistoryCount: Int = 50 {
        didSet {
            defaults.set(maxHistoryCount, forKey: keyMaxHistoryCount)
            if isInitialized {
                ClipboardManager.shared.trimHistoryIfNeeded()
            }
        }
    }

    public var historyRetentionDays: Int = 0 { // 0 = Forever
        didSet {
            defaults.set(historyRetentionDays, forKey: keyRetentionDays)
            if isInitialized {
                ClipboardManager.shared.purgeExpiredHistory()
            }
        }
    }

    public var maskSensitiveContent: Bool = true {
        didSet { defaults.set(maskSensitiveContent, forKey: keyMaskSensitive) }
    }

    public var syncSensitiveContent: Bool = false {
        didSet { defaults.set(syncSensitiveContent, forKey: keySyncSensitive) }
    }

    public var clearHistoryOnQuit: Bool = false {
        didSet { defaults.set(clearHistoryOnQuit, forKey: keyClearOnQuit) }
    }

    public var ignorePasswordManagerCopies: Bool = false {
        didSet { defaults.set(ignorePasswordManagerCopies, forKey: keyIgnoreConcealed) }
    }

    public var enableNumberShortcuts: Bool = true {
        didSet { defaults.set(enableNumberShortcuts, forKey: keyEnableNumberShortcuts) }
    }

    public var hotKeyPreset: HotKeyPreset = .cmdShiftV {
        didSet {
            defaults.set(hotKeyPreset.rawValue, forKey: keyHotKeyPreset)
            if isInitialized {
                HotKeyManager.shared.applyCurrentPreset()
            }
        }
    }

    public var excludedAppBundleIdentifiers: [String] = [] {
        didSet { defaults.set(excludedAppBundleIdentifiers, forKey: keyExcludedApps) }
    }

    public var excludedWebDomains: [String] = [] {
        didSet { defaults.set(excludedWebDomains, forKey: keyExcludedDomains) }
    }

    public var syncIntervalMinutes: Int = 5 {
        didSet { defaults.set(syncIntervalMinutes, forKey: keySyncInterval) }
    }

    public var appearanceTheme: AppTheme = .system {
        didSet {
            defaults.set(appearanceTheme.rawValue, forKey: keyTheme)
            applyTheme()
        }
    }

    public var onThemeChange: ((AppTheme) -> Void)?

    // MARK: - Initialization
    private init() {
        // Register default values
        defaults.register(defaults: [
            keyLaunchAtLogin: false,
            keyShowNotificationOnCopy: true,
            keyPlaySoundOnCopy: true,
            keyMaxHistoryCount: 50,
            keyRetentionDays: 0,
            keyMaskSensitive: true,
            keySyncSensitive: false,
            keyClearOnQuit: false,
            keyIgnoreConcealed: false,
            keyHotKeyPreset: HotKeyPreset.cmdShiftV.rawValue,
            keyEnableNumberShortcuts: true,
            keyExcludedApps: ["com.agilebits.onepassword7", "com.1password.1password", "com.bitwarden.desktop", "com.keepersecurity.passwordmanager"],
            keyExcludedDomains: [],
            keySyncInterval: 5,
            keyTheme: AppTheme.system.rawValue
        ])

        self.showNotificationsOnCopy = defaults.bool(forKey: keyShowNotificationOnCopy)
        self.playSoundOnCopy = defaults.bool(forKey: keyPlaySoundOnCopy)
        self.maxHistoryCount = defaults.integer(forKey: keyMaxHistoryCount) == 0 ? 50 : defaults.integer(forKey: keyMaxHistoryCount)
        self.historyRetentionDays = defaults.integer(forKey: keyRetentionDays)
        self.maskSensitiveContent = defaults.bool(forKey: keyMaskSensitive)
        self.syncSensitiveContent = defaults.bool(forKey: keySyncSensitive)
        self.clearHistoryOnQuit = defaults.bool(forKey: keyClearOnQuit)
        self.ignorePasswordManagerCopies = defaults.bool(forKey: keyIgnoreConcealed)
        self.enableNumberShortcuts = defaults.bool(forKey: keyEnableNumberShortcuts)
        self.excludedAppBundleIdentifiers = defaults.stringArray(forKey: keyExcludedApps) ?? []
        self.excludedWebDomains = defaults.stringArray(forKey: keyExcludedDomains) ?? []

        let presetString = defaults.string(forKey: keyHotKeyPreset) ?? HotKeyPreset.cmdShiftV.rawValue
        self.hotKeyPreset = HotKeyPreset(rawValue: presetString) ?? .cmdShiftV

        let syncInterval = defaults.integer(forKey: keySyncInterval)
        self.syncIntervalMinutes = syncInterval == 0 ? 5 : syncInterval

        let themeString = defaults.string(forKey: keyTheme) ?? AppTheme.system.rawValue
        self.appearanceTheme = AppTheme(rawValue: themeString) ?? .system

        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = defaults.bool(forKey: keyLaunchAtLogin)
        }

        self.isInitialized = true
        applyTheme()
    }

    public func addExcludedApp(bundleId: String) {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !excludedAppBundleIdentifiers.contains(trimmed) else { return }
        excludedAppBundleIdentifiers.append(trimmed)
    }

    public func removeExcludedApp(bundleId: String) {
        excludedAppBundleIdentifiers.removeAll { $0 == bundleId }
    }

    public func addExcludedDomain(_ input: String) {
        var clean = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        clean = clean.replacingOccurrences(of: "https://", with: "")
        clean = clean.replacingOccurrences(of: "http://", with: "")
        clean = clean.replacingOccurrences(of: "www.", with: "")
        if clean.hasPrefix("*.") {
            clean = String(clean.dropFirst(2))
        }
        if let slashIndex = clean.firstIndex(of: "/") {
            clean = String(clean[..<slashIndex])
        }
        guard !clean.isEmpty, !excludedWebDomains.contains(clean) else { return }
        excludedWebDomains.append(clean)
    }

    public func removeExcludedDomain(_ domain: String) {
        excludedWebDomains.removeAll { $0.caseInsensitiveCompare(domain) == .orderedSame }
    }

    public func isDomainOrURLBlocked(_ urlOrDomainString: String) -> Bool {
        var clean = urlOrDomainString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: clean), let host = url.host {
            clean = host.lowercased()
        }
        clean = clean.replacingOccurrences(of: "https://", with: "")
        clean = clean.replacingOccurrences(of: "http://", with: "")
        clean = clean.replacingOccurrences(of: "www.", with: "")
        if let slashIndex = clean.firstIndex(of: "/") {
            clean = String(clean[..<slashIndex])
        }

        for blocked in excludedWebDomains {
            var blockedClean = blocked.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            blockedClean = blockedClean.replacingOccurrences(of: "https://", with: "")
            blockedClean = blockedClean.replacingOccurrences(of: "http://", with: "")
            blockedClean = blockedClean.replacingOccurrences(of: "www.", with: "")
            if blockedClean.hasPrefix("*.") {
                blockedClean = String(blockedClean.dropFirst(2))
            }
            if let slashIndex = blockedClean.firstIndex(of: "/") {
                blockedClean = String(blockedClean[..<slashIndex])
            }

            guard !blockedClean.isEmpty else { continue }
            if clean == blockedClean || clean.hasSuffix("." + blockedClean) || clean.contains(blockedClean) {
                return true
            }
        }
        return false
    }

    private func updateLaunchAtLoginState(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update LaunchAtLogin: \(error)")
            }
        }
    }

    public func applyTheme() {
        NSApp.appearance = appearanceTheme.nsAppearance
        onThemeChange?(appearanceTheme)
    }

    public static func openSettingsWindow() {
        SettingsWindowController.shared.show()
    }
}

/// Dedicated window controller to reliably display the settings panel anywhere.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environment(ClipboardManager.shared)

        let hostingController = NSHostingController(rootView: settingsView)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.contentMinSize = NSSize(width: 720, height: 640)
        newWindow.center()
        newWindow.setFrameAutosaveName("SyncBoardSettingsWindow")
        newWindow.title = "SyncBoard Settings"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Window closed by user
    }
}
