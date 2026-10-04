//
//  SettingsView.swift
//  SyncBoard
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var driveSync = GoogleDriveSyncManager.shared
    @State private var customThemeManager = CustomArtThemeManager.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var showResetConfirmation = false
    @State private var newExcludedAppBundleId = ""
    @State private var newExcludedDomain = ""
    @State private var showAdvancedBundleIdField = false

    // Custom Art Theme Upload State
    @State private var showAddThemeSheet = false
    @State private var newThemeName = ""
    @State private var newLightSvgData: Data? = nil
    @State private var newLightSvgName: String = ""
    @State private var newDarkSvgData: Data? = nil
    @State private var newDarkSvgName: String = ""
    @State private var uploadErrorMessage: String? = nil
    @State private var selectedArtTypeTab: ArtTypeTab = .defaultArt

    enum ArtTypeTab: String, CaseIterable, Identifiable {
        case defaultArt = "Default Art"
        case customArt = "Custom Art"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .defaultArt: return "sparkles"
            case .customArt: return "paintpalette"
            }
        }
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case hotkeys = "Shortcuts"
        case privacy = "Privacy"
        case sync = "Google Drive"
        case devices = "Devices"
        case appearance = "Appearance"
        case about = "About"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .general: return "gearshape"
            case .hotkeys: return "command"
            case .privacy: return "lock.shield"
            case .sync: return "arrow.triangle.2.circlepath.icloud"
            case .devices: return "laptopcomputer.and.iphone"
            case .appearance: return "paintpalette"
            case .about: return "info.circle"
            }
        }

        var iconTint: Color {
            switch self {
            case .general: return .blue
            case .hotkeys: return .purple
            case .privacy: return .red
            case .sync: return .green
            case .devices: return .teal
            case .appearance: return .pink
            case .about: return .gray
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation (Fixed width to completely eliminate layout shifts)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(tab.iconTint)
                                    .frame(width: 22, height: 22)
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 180)
            .background(Color.primaryBackground)

            Divider()

            // Detail Content Pane
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    tabContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .scrollControlSize(.mini)
            }
            .scrollControlSize(.mini)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primaryBackground)
        }
        .frame(width: 720, height: 640)
        .preferredColorScheme(settings.appearanceTheme.colorScheme)
    }

    // MARK: - Tab Content Router
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalSettingsSection
        case .hotkeys:
            hotkeySettingsSection
        case .privacy:
            privacySettingsSection
        case .sync:
            syncSettingsSection
        case .devices:
            devicesSettingsSection
        case .appearance:
            appearanceSettingsSection
        case .about:
            aboutSection
        }
    }

    // MARK: - 1. General Settings
    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView(title: "General Settings", subtitle: "Configure startup behavior, history capacity, and audio/visual cues.")

            settingsCard("Startup & Notifications") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Launch SyncBoard at login", isOn: $settings.launchAtLogin)
                        .controlSize(.regular)

                    Toggle("Show copy feedback toast overlay", isOn: $settings.showNotificationsOnCopy)
                        .controlSize(.regular)

                    Toggle("Play sound when copying content", isOn: $settings.playSoundOnCopy)
                        .controlSize(.regular)
                }
            }

            settingsCard("History Capacity & Expiration") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Maximum History Items:")
                                .font(.body)
                            Spacer()
                            Text("\(settings.maxHistoryCount)")
                                .font(.body.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }

                        AppPillTabs(
                            selection: $settings.maxHistoryCount,
                            items: [25, 50, 100, 200, 500],
                            title: { "\($0) Items" }
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("History Retention Period:")
                                .font(.body)
                            Spacer()
                            Text(settings.historyRetentionDays == 0 ? "Keep Forever" : "\(settings.historyRetentionDays) Days")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }

                        AppPillTabs(
                            selection: $settings.historyRetentionDays,
                            items: [0, 7, 30, 90],
                            title: { $0 == 0 ? "Forever" : "\($0) Days" }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 2. Shortcut Settings
    private var hotkeySettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView(title: "Shortcuts & Keybindings", subtitle: "Customize the global shortcut to summon SyncBoard from any application.")

            settingsCard("Summon Shortcut") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Global Shortcut:", selection: $settings.hotKeyPreset) {
                        ForEach(AppSettings.HotKeyPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)

                    Text("Press this keyboard combination from any active window on macOS to instantly bring up your clipboard history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard("Quick Selection") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable ⌘1 - ⌘9 quick copy shortcuts in popover", isOn: $settings.enableNumberShortcuts)
                        .controlSize(.regular)

                    Text("When the menu bar popover is open, pressing ⌘ + Number directly pastes the corresponding item.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard("Keyboard Shortcuts & Tips") {
                VStack(spacing: 10) {
                    shortcutReferenceRow(label: "Summon Popover", description: "Open popup from anywhere", shortcut: settings.hotKeyPreset.rawValue)
                    Divider()
                    shortcutReferenceRow(label: "Focus Search Bar", description: "Quickly search history or notes", shortcut: "⌘ K")
                    Divider()
                    shortcutReferenceRow(label: "Copy Selected Item", description: "Copy clipboard or note content", shortcut: "⌘ C")
                    Divider()
                    shortcutReferenceRow(label: "Quick Select & Paste", description: "Paste slot 1 to 9 in popover", shortcut: "⌘ 1 – ⌘ 9")
                    Divider()
                    shortcutReferenceRow(label: "Open Settings", description: "Access preferences window", shortcut: "⌘ ,")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcutReferenceRow(label: String, description: String, shortcut: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(shortcut)
                .font(.caption.monospaced())
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - 3. Privacy Settings
    private var privacySettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView(title: "Privacy & Protection", subtitle: "Protect sensitive credentials, passwords, and exclude private applications and websites.")

            settingsCard("Content Masking & Safety") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Mask sensitive content (API keys, passwords, tokens, cards)", isOn: $settings.maskSensitiveContent)
                        .controlSize(.regular)

                    Toggle("Ignore concealed copies from password managers (1Password, Bitwarden, etc.)", isOn: $settings.ignorePasswordManagerCopies)
                        .controlSize(.regular)

                    Toggle("Clear unpinned history upon quitting SyncBoard", isOn: $settings.clearHistoryOnQuit)
                        .controlSize(.regular)
                }
            }

            // MARK: - Excluded Applications (Blacklist)
            settingsCard("Excluded Applications (Blacklist)") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SyncBoard will never record copies made while you are working in these applications:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settings.excludedAppBundleIdentifiers.isEmpty {
                        Text("No excluded applications.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(settings.excludedAppBundleIdentifiers, id: \.self) { bundleId in
                                HStack(spacing: 12) {
                                    appIconView(for: bundleId)
                                        .frame(width: 26, height: 26)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(appName(for: bundleId))
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Text(bundleId)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            settings.removeExcludedApp(bundleId: bundleId)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.callout)
                                            .foregroundStyle(.red)
                                            .padding(6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    // Native Application Picker & Running Apps Selector
                    HStack(spacing: 12) {
                        Button {
                            selectAppViaFilePicker()
                        } label: {
                            Label("Choose Application...", systemImage: "plus.app")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Menu {
                            ForEach(runningApplications(), id: \.bundleId) { appInfo in
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        settings.addExcludedApp(bundleId: appInfo.bundleId)
                                    }
                                } label: {
                                    HStack {
                                        Text(appInfo.name)
                                        Spacer()
                                        Text(appInfo.bundleId)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } label: {
                            Label("Add Running App", systemImage: "macwindow.on.rectangle")
                                .font(.body)
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.regular)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showAdvancedBundleIdField.toggle()
                            }
                        } label: {
                            Image(systemName: showAdvancedBundleIdField ? "chevron.up" : "ellipsis")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Add custom bundle ID manually")
                    }
                    .padding(.top, 6)

                    if showAdvancedBundleIdField {
                        HStack(spacing: 10) {
                            TextField("Enter bundle ID (e.g. com.example.app)", text: $newExcludedAppBundleId)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.regular)
                                .labelsHidden()

                            Button("Add") {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    settings.addExcludedApp(bundleId: newExcludedAppBundleId)
                                    newExcludedAppBundleId = ""
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .disabled(newExcludedAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            // MARK: - Excluded Websites & Domains (URL Blacklist)
            settingsCard("Excluded Websites & Domains (URL Blacklist)") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SyncBoard will ignore and never record copied text or links from these website domains:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if settings.excludedWebDomains.isEmpty {
                        Text("No excluded websites.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(settings.excludedWebDomains, id: \.self) { domain in
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 26, height: 26)

                                    Text(domain)
                                        .font(.callout.monospaced())
                                        .fontWeight(.medium)

                                    Spacer()

                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            settings.removeExcludedDomain(domain)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.callout)
                                            .foregroundStyle(.red)
                                            .padding(6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("Enter website URL or domain (e.g. github.com, bank.com)", text: $newExcludedDomain)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)
                            .labelsHidden()
                            .onSubmit {
                                let trimmed = newExcludedDomain.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        settings.addExcludedDomain(trimmed)
                                        newExcludedDomain = ""
                                    }
                                }
                            }

                        Button("Add Website") {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                settings.addExcludedDomain(newExcludedDomain)
                                newExcludedDomain = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(newExcludedDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 4)
                }
            }

            settingsCard("Data Management") {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reset All History")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Permanently erase all clipboard history records across this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Text("Erase Everything")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.regular)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "Erase All Clipboard History?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase Everything", role: .destructive) {
                clipboardManager.clearAll(preservePinned: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All saved clips and pins will be permanently deleted.")
        }
    }

    // MARK: - 4. Sync Settings
    private var syncSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView(title: "Google Drive Cloud Sync", subtitle: "Keep your clipboard history seamlessly synchronized between macOS and Windows.")

            settingsCard("Account Status") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Image(systemName: driveSync.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 26))
                            .foregroundStyle(driveSync.isConnected ? Color.green : Color.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(driveSync.isConnected ? "Connected to Google Drive" : "Disconnected")
                                .font(.body)
                                .fontWeight(.semibold)

                            if let email = driveSync.accountEmail {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Sign in to synchronize your clipboard items across all your devices.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if driveSync.isConnected {
                            Button("Disconnect", role: .destructive) {
                                driveSync.disconnect()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        } else {
                            Button("Connect Account") {
                                Task { await driveSync.connect() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if driveSync.isConnected {
                settingsCard("Sync Preferences") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Sync Frequency:", selection: $settings.syncIntervalMinutes) {
                            Text("Every 1 Minute").tag(1)
                            Text("Every 5 Minutes").tag(5)
                            Text("Every 15 Minutes").tag(15)
                            Text("Every 30 Minutes").tag(30)
                        }
                        .pickerStyle(.menu)
                        .controlSize(.regular)

                        Toggle("Sync masked & sensitive items to cloud storage", isOn: $settings.syncSensitiveContent)
                            .controlSize(.regular)

                        HStack {
                            if let lastSync = driveSync.lastSyncedAt {
                                Text("Last synced: \(lastSync.formatted(date: .omitted, time: .standard))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                driveSync.syncNow()
                            } label: {
                                Label("Sync Now", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .disabled(driveSync.isSyncing)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 4b. Devices Settings
    private var devicesSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView(title: "Connected Devices", subtitle: "See every device signed in to this Google Drive account and disconnect any you no longer recognize.")

            if !driveSync.isConnected {
                settingsCard("Signed-In Devices") {
                    Text("Connect your Google Drive account on the Google Drive tab to see devices signed in to this clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                settingsCard("Signed-In Devices") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Devices that have synced clipboard history to this account.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                Task { await driveSync.refreshDevices() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(driveSync.isLoadingDevices)
                        }

                        if driveSync.devices.isEmpty {
                            Text(driveSync.isLoadingDevices ? "Loading devices…" : "No devices found yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(driveSync.devices.sorted(by: { $0.lastSeenAt > $1.lastSeenAt })) { device in
                                    deviceRow(device)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            if driveSync.isConnected {
                // Register/refresh this device's entry so it shows up even if
                // it hasn't synced since connecting (e.g. an already-connected
                // account opening this tab for the first time).
                await driveSync.registerCurrentDevice()
            }
        }
    }

    private func deviceRow(_ device: DeviceSession) -> some View {
        let isCurrentDevice = device.id == DeviceIdentity.currentID

        return HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if isCurrentDevice {
                        Text("This Device")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                }

                Text("\(device.osName) \(device.osVersion) · Signed in \(device.loginDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Last active \(device.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Disconnect", role: .destructive) {
                Task { await driveSync.disconnectDevice(device.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 5. Appearance Settings
    private var appearanceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView(title: "Appearance & Theme", subtitle: "Personalize SyncBoard's visual style, dark mode preferences, and custom vector art themes.")

            settingsCard("Theme Selection") {
                VStack(alignment: .leading, spacing: 16) {
                    AppPillTabs(
                        selection: $settings.appearanceTheme,
                        title: { $0.rawValue }
                    )

                    HStack(spacing: 16) {
                        themePreviewCard(title: "System", icon: "circle.lefthalf.filled", isSelected: settings.appearanceTheme == .system)
                            .onTapGesture { settings.appearanceTheme = .system }
                        themePreviewCard(title: "Light", icon: "sun.max.fill", isSelected: settings.appearanceTheme == .light)
                            .onTapGesture { settings.appearanceTheme = .light }
                        themePreviewCard(title: "Dark", icon: "moon.stars.fill", isSelected: settings.appearanceTheme == .dark)
                            .onTapGesture { settings.appearanceTheme = .dark }
                    }
                }
            }

            // MARK: - Art Theme Customization (SVG)
            settingsCard("Note Art Themes (Vector SVG)") {
                VStack(alignment: .leading, spacing: 16) {
                    // Storage & Actions Banner
                    artThemeStorageAndActionsBanner

                    Divider()

                    // Default Art vs Custom Art Pill Tabs
                    AppPillTabs(
                        selection: $selectedArtTypeTab,
                        items: ArtTypeTab.allCases,
                        title: { tab in
                            switch tab {
                            case .defaultArt:
                                return "Default Art"
                            case .customArt:
                                return "Custom Art (\(customThemeManager.customThemes.count))"
                            }
                        },
                        icon: { $0.icon },
                        isCompact: true
                    )

                    // Tab Content
                    if selectedArtTypeTab == .defaultArt {
                        VStack(alignment: .leading, spacing: 16) {
                            themeSectionGroup(title: "PLACES & TRAVEL", icon: "map.fill", themes: [.places, .travel])
                            themeSectionGroup(title: "FOOD & GROCERY", icon: "fork.knife", themes: [.food, .grocery, .recipe])
                            themeSectionGroup(title: "LIFESTYLE, MUSIC & MEDIA", icon: "music.note", themes: [.music, .notes, .video, .celebration])
                        }
                    } else {
                        customThemesSectionGroup
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showAddThemeSheet) {
            addCustomThemeSheetView
        }
    }

    // MARK: - Art Theme Storage & Actions Banner
    private var artThemeStorageAndActionsBanner: some View {
        HStack(spacing: 14) {
            // Storage Stats Card (Equal Height)
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Device Disk Usage")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(customThemeManager.formattedTotalStorage)
                            .font(.callout.monospacedDigit())
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)
                        Text("(\(customThemeManager.customThemes.count) \(customThemeManager.customThemes.count == 1 ? "theme" : "themes"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // Upload Theme Action Card (Equal Height)
            Button {
                resetUploadForm()
                showAddThemeSheet = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 28, height: 28)
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Upload SVG Theme")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Text("Light & Dark .svg files")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 220, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .shadow(color: Color.accentColor.opacity(0.25), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
    }

    private func themeSectionGroup(title: String, icon: String, themes: [NoteTheme]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 10)], spacing: 10) {
                ForEach(themes) { theme in
                    artThemeCard(theme: theme)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }

    private func artThemeCard(theme: NoteTheme) -> some View {
        VStack(spacing: 8) {
            KeepThemeAssets.thumbnail(for: theme, isDark: settings.appearanceTheme == .dark, size: 48)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)

            Text(theme.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Text("Built-in SVG")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    private var customThemesSectionGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text("CUSTOM UPLOADED THEMES (\(customThemeManager.customThemes.count))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if customThemeManager.customThemes.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No custom SVG themes uploaded yet")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("Upload custom Light and Dark vector files using the button above.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    ForEach(customThemeManager.customThemes) { customTheme in
                        customThemeRow(customTheme)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Custom Theme Row
    private func customThemeRow(_ theme: CustomArtTheme) -> some View {
        HStack(spacing: 12) {
            // Dual Light & Dark Thumbnails
            HStack(spacing: 8) {
                VStack(spacing: 3) {
                    customThemeManager.thumbnail(for: theme.id, isDark: false, size: 34)
                    Text("Light")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 3) {
                    customThemeManager.thumbnail(for: theme.id, isDark: true, size: 34)
                    Text("Dark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.name)
                    .font(.body)
                    .fontWeight(.semibold)

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 9))
                        Text(theme.formattedSize)
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(Color.accentColor)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("Added \(theme.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                withAnimation {
                    customThemeManager.deleteTheme(id: theme.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .help("Delete custom theme and free storage")
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Add Custom Theme Sheet Modal
    private var addCustomThemeSheetView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upload Custom SVG Theme")
                        .font(.headline)
                    Text("Only vector .SVG files are accepted. You must provide both Light & Dark variants.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    showAddThemeSheet = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if let error = uploadErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(8)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Theme Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Theme Name")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                TextField("e.g. Minimal Floral, Neon Grid, Sunset", text: $newThemeName)
                    .textFieldStyle(.roundedBorder)
            }

            // Two SVG Variant Slots
            HStack(spacing: 16) {
                // Light Mode Variant
                svgVariantPickerBox(
                    title: "Light Mode Variant",
                    subtitle: "Rendered when app is in Light appearance",
                    isDark: false,
                    data: newLightSvgData,
                    filename: newLightSvgName
                )

                // Dark Mode Variant
                svgVariantPickerBox(
                    title: "Dark Mode Variant",
                    subtitle: "Rendered when app is in Dark appearance",
                    isDark: true,
                    data: newDarkSvgData,
                    filename: newDarkSvgName
                )
            }

            Spacer()

            // Footer actions
            HStack {
                Button("Cancel") {
                    showAddThemeSheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                let canSave = !newThemeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              newLightSvgData != nil &&
                              newDarkSvgData != nil

                Button("Save Theme") {
                    saveUploadedTheme()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 540, height: 440)
    }

    // MARK: - SVG Variant Picker Box
    private func svgVariantPickerBox(
        title: String,
        subtitle: String,
        isDark: Bool,
        data: Data?,
        filename: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDark ? Color.black.opacity(0.8) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(data != nil ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: data != nil ? 1.5 : 1)
                    )

                if let data = data, let img = NSImage(data: data) {
                    VStack(spacing: 6) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(filename)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(isDark ? .white : .black)
                            Text("(\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("Select .SVG File")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(isDark ? .white : .primary)
                    }
                }
            }
            .frame(height: 120)
            .contentShape(Rectangle())
            .onTapGesture {
                pickSvgFile(isDark: isDark)
            }

            Button(data != nil ? "Change SVG" : "Choose SVG...") {
                pickSvgFile(isDark: isDark)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Upload Helpers
    private func resetUploadForm() {
        newThemeName = ""
        newLightSvgData = nil
        newLightSvgName = ""
        newDarkSvgData = nil
        newDarkSvgName = ""
        uploadErrorMessage = nil
    }

    private func pickSvgFile(isDark: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml]

        if panel.runModal() == .OK, let url = panel.url {
            guard url.pathExtension.lowercased() == "svg" else {
                uploadErrorMessage = "Only .SVG vector files are supported."
                return
            }
            do {
                let data = try Data(contentsOf: url)
                guard let _ = NSImage(data: data) else {
                    uploadErrorMessage = "The selected file is not a valid SVG."
                    return
                }
                uploadErrorMessage = nil
                if isDark {
                    newDarkSvgData = data
                    newDarkSvgName = url.lastPathComponent
                } else {
                    newLightSvgData = data
                    newLightSvgName = url.lastPathComponent
                }
            } catch {
                uploadErrorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        }
    }

    private func saveUploadedTheme() {
        guard let lightData = newLightSvgData, let darkData = newDarkSvgData else {
            uploadErrorMessage = "Both Light and Dark SVG variants must be provided."
            return
        }
        do {
            _ = try customThemeManager.addTheme(
                name: newThemeName,
                lightSvgData: lightData,
                darkSvgData: darkData
            )
            showAddThemeSheet = false
            resetUploadForm()
        } catch {
            uploadErrorMessage = error.localizedDescription
        }
    }

    private func themePreviewCard(title: String, icon: String, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 6. About Section
    private var aboutSection: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .shadow(radius: 4)

            VStack(spacing: 4) {
                Text("SyncBoard")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Version 1.0 (Build 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Cross-Platform Clipboard Manager for macOS & Windows")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Label("Crafted with native SwiftUI & AppKit", systemImage: "apple.logo")
                Label("Secured via macOS Keychain & Google Cloud Drive", systemImage: "lock.shield")
                Label("Fast ULID indexing with memory-efficient local caching", systemImage: "bolt.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - App Picker Helpers
    private func selectAppViaFilePicker() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Application to Exclude"
        openPanel.prompt = "Exclude Application"
        openPanel.allowedContentTypes = [.application]
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")

        if openPanel.runModal() == .OK {
            for url in openPanel.urls {
                if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        settings.addExcludedApp(bundleId: bundleId)
                    }
                }
            }
        }
    }

    private func runningApplications() -> [(name: String, bundleId: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleId = app.bundleIdentifier,
                      let name = app.localizedName,
                      bundleId != Bundle.main.bundleIdentifier else { return nil }
                return (name: name, bundleId: bundleId)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func appName(for bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url),
           let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String ?? bundle.infoDictionary?["CFBundleName"] as? String {
            return name
        }
        return bundleId.components(separatedBy: ".").last?.capitalized ?? bundleId
    }

    @ViewBuilder
    private func appIconView(for bundleId: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func headerView(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    SettingsView()
        .environment(ClipboardManager.shared)
}
