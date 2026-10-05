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
    private let driveClient: GoogleDriveAppDataClient
    private let historyFile: GoogleDriveJSONFile<ClipboardItem>
    private let todoFile: GoogleDriveJSONFile<TodoItem>
    private let notesFile: GoogleDriveJSONFile<QuickNote>
    private let noteHistoryFile: GoogleDriveJSONFile<NoteRevision>
    private let deviceService: GoogleDriveDeviceService
    private var syncTimer: Timer?
    private var debounceTask: Task<Void, Never>?
    private var needsResync = false

    private init() {
        let client = GoogleDriveAppDataClient(authManager: .shared)
        driveClient = client
        historyFile = GoogleDriveJSONFile(name: GoogleDriveSyncService.fileName, client: client)
        todoFile = GoogleDriveJSONFile(name: GoogleDriveTodoService.fileName, client: client)
        notesFile = GoogleDriveJSONFile(name: GoogleDriveNotesService.fileName, client: client)
        noteHistoryFile = GoogleDriveJSONFile(name: GoogleDriveNoteHistoryService.fileName, client: client)
        deviceService = GoogleDriveDeviceService(client: client)
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
    private func heartbeatCurrentDevice(remote: DriveAppDataFile?) async -> Error? {
        do {
            let updated = try await deviceService.heartbeatCurrentDevice(remote: remote)
            if updated.contains(where: { $0.id == DeviceIdentity.currentID }) {
                devices = updated
            } else {
                disconnect()
            }
            return nil
        } catch {
            return error
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
        syncTimer?.tolerance = interval * 0.1
    }

    func startPeriodicSync() {
        startSyncTimer()
        syncNow()
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

    /// Requests made while a sync is in flight are queued as one follow-up
    /// run so a change made mid-sync isn't left waiting for the next timer tick.
    func syncNow() {
        guard isConnected else { return }
        guard !isSyncing else {
            needsResync = true
            return
        }
        isSyncing = true
        Task {
            await performSync()
            isSyncing = false
            if needsResync {
                needsResync = false
                syncNow()
            }
        }
    }

    /// One listing request returns every file's version, then the four files
    /// sync concurrently; unchanged files cost no further requests.
    private func performSync() async {
        let remoteFiles: [String: DriveAppDataFile]
        do {
            remoteFiles = try await driveClient.listFiles()
        } catch {
            lastError = error.localizedDescription
            return
        }

        async let historyError = syncHistory(remote: remoteFiles[GoogleDriveSyncService.fileName])
        async let todoError = syncTodos(remote: remoteFiles[GoogleDriveTodoService.fileName])
        async let notesError = syncNotes(
            remote: remoteFiles[GoogleDriveNotesService.fileName],
            historyRemote: remoteFiles[GoogleDriveNoteHistoryService.fileName]
        )
        async let deviceError = heartbeatCurrentDevice(remote: remoteFiles[GoogleDriveDeviceService.fileName])

        let errors = await [historyError, todoError, notesError, deviceError].compactMap { $0 }
        if let error = errors.first {
            lastError = error.localizedDescription
        } else {
            lastSyncedAt = Date()
            lastError = nil
        }
    }

    // Each sync re-merges with the current local state afterwards so edits
    // made during the network round trip aren't overwritten.

    private func syncHistory(remote: DriveAppDataFile?) async -> Error? {
        let localHistory = ClipboardManager.shared.history
        let itemsToSync = AppSettings.shared.syncSensitiveContent
            ? localHistory
            : localHistory.filter { !$0.isSensitive }
        do {
            let merged = try await historyFile.update(remote: remote) { remoteHistory in
                GoogleDriveSyncService.merge(local: itemsToSync, remote: remoteHistory)
            }
            let latest = GoogleDriveSyncService.merge(local: ClipboardManager.shared.history, remote: merged)
            ClipboardManager.shared.replaceHistory(with: latest)
            return nil
        } catch {
            return error
        }
    }

    private func syncTodos(remote: DriveAppDataFile?) async -> Error? {
        let localItems = TodoManager.shared.syncItems
        do {
            let merged = try await todoFile.update(remote: remote) { remoteItems in
                GoogleDriveTodoService.merge(local: localItems, remote: remoteItems)
            }
            let latest = GoogleDriveTodoService.merge(local: TodoManager.shared.syncItems, remote: merged)
            TodoManager.shared.replaceItems(with: latest)
            return nil
        } catch {
            return error
        }
    }

    /// Content changes this sync pushes to Drive are also appended to the note history file.
    private func syncNotes(remote: DriveAppDataFile?, historyRemote: DriveAppDataFile?) async -> Error? {
        let localNotes = QuickNoteManager.shared.syncNotes
        var uploadedChanges: [QuickNote] = []
        do {
            let merged = try await notesFile.update(remote: remote) { remoteNotes in
                let merged = GoogleDriveNotesService.merge(local: localNotes, remote: remoteNotes)
                uploadedChanges = GoogleDriveNoteHistoryService.contentChanges(in: merged, comparedTo: remoteNotes)
                return merged
            }
            let latest = GoogleDriveNotesService.merge(local: QuickNoteManager.shared.syncNotes, remote: merged)
            QuickNoteManager.shared.replaceNotes(with: latest)

            if !uploadedChanges.isEmpty {
                _ = try await noteHistoryFile.update(remote: historyRemote) { revisions in
                    GoogleDriveNoteHistoryService.record(uploadedChanges, into: revisions)
                }
            }
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Note history

    /// Newest first. Reuses the cached file contents when Drive's version is unchanged.
    func noteHistory(for noteID: String) async throws -> [NoteRevision] {
        let revisions = try await noteHistoryFile.read(remote: noteHistoryFile.metadata())
        return revisions
            .filter { $0.noteID == noteID }
            .sorted { $0.savedAt > $1.savedAt }
    }
}
