//
//  GoogleDriveSyncManager.swift
//  SyncBoard
//

import Observation
import SwiftUI

/// Coordinates background sync cadence and glues `ClipboardManager` to
/// `GoogleDriveSyncService`. Views observe this instead of talking to the
/// actor directly.
@MainActor
@Observable
final class GoogleDriveSyncManager {
    static let shared = GoogleDriveSyncManager()

    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?

    private(set) var devices: [DeviceSession] = []
    private(set) var isLoadingDevices = false

    var isConnected: Bool { auth.isConnected }
    var accountEmail: String? { auth.accountEmail }

    private let auth = GoogleDriveAuthManager.shared
    private let deviceService = GoogleDriveDeviceService()
    private var syncTimer: Timer?
    private var debounceTask: Task<Void, Never>?

    private init() {
        startSyncTimer()
    }

    // MARK: - Auth passthrough

    func connect() async {
        lastError = nil
        do {
            try await auth.connect()
            // Immediately pull remote history on first connect
            syncNow()
            await registerCurrentDevice()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        auth.disconnect()
        lastSyncedAt = nil
        lastError = nil
        devices = []
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: - Device management

    func refreshDevices() async {
        guard isConnected else { return }
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        do {
            devices = try await deviceService.fetchDevices()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func registerCurrentDevice() async {
        guard isConnected else { return }
        do {
            devices = try await deviceService.registerCurrentDevice()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Removes a device from the shared registry. Removing this device
    /// also signs it out locally; removing another device merely revokes
    /// its registry entry, which that device notices on its next sync.
    func disconnectDevice(_ id: String) async {
        do {
            devices = try await deviceService.removeDevice(id: id)
            if id == DeviceIdentity.currentID {
                disconnect()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Refreshes this device's "last seen" timestamp, or signs it out
    /// locally if another device has since revoked it from the registry.
    private func heartbeatCurrentDevice() async {
        guard isConnected else { return }
        do {
            let updated = try await deviceService.heartbeatCurrentDevice()
            if updated.contains(where: { $0.id == DeviceIdentity.currentID }) {
                devices = updated
            } else {
                disconnect()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sync control

    func startSyncTimer() {
        syncTimer?.invalidate()
        let interval = TimeInterval(AppSettings.shared.syncIntervalMinutes * 60)
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncNow()
            }
        }
    }

    func startPeriodicSync() {
        startSyncTimer()
    }

    func restartPeriodicSync() {
        startSyncTimer()
    }

    func restartSyncTimer() {
        startSyncTimer()
    }

    /// Call whenever a new local item is added/deleted so changes propagate
    /// quickly without spamming the API on every keystroke.
    func scheduleSync() {
        guard isConnected else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    func syncNow() {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            do {
                let service = GoogleDriveSyncService(authManager: auth)
                let localHistory = ClipboardManager.shared.history

                let itemsToSync: [ClipboardItem]
                if AppSettings.shared.syncSensitiveContent {
                    itemsToSync = localHistory
                } else {
                    itemsToSync = localHistory.filter { !$0.isSensitive }
                }

                let merged = try await service.sync(localHistory: itemsToSync)

                if !AppSettings.shared.syncSensitiveContent {
                    // Re-inject local sensitive items so they aren't lost from memory
                    let sensitiveLocals = localHistory.filter { $0.isSensitive }
                    let combined = GoogleDriveSyncService.merge(local: sensitiveLocals, remote: merged)
                    ClipboardManager.shared.replaceHistory(with: combined)
                } else {
                    ClipboardManager.shared.replaceHistory(with: merged)
                }

                lastSyncedAt = Date()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }

            do {
                let todoService = GoogleDriveTodoService(authManager: auth)
                let mergedItems = try await todoService.sync(localItems: TodoManager.shared.syncItems)
                // Re-merge with current local state so tasks created/edited during the upload aren't dropped.
                let latestItems = GoogleDriveTodoService.merge(local: TodoManager.shared.syncItems, remote: mergedItems)
                TodoManager.shared.replaceItems(with: latestItems)
            } catch {
                lastError = error.localizedDescription
            }

            do {
                let notesService = GoogleDriveNotesService(authManager: auth)
                let mergedNotes = try await notesService.sync(localNotes: QuickNoteManager.shared.syncNotes)
                let latestNotes = GoogleDriveNotesService.merge(local: QuickNoteManager.shared.syncNotes, remote: mergedNotes)
                QuickNoteManager.shared.replaceNotes(with: latestNotes)
            } catch {
                lastError = error.localizedDescription
            }

            await heartbeatCurrentDevice()
        }
    }
}
