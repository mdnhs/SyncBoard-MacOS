//
//  GoogleDriveSyncManager.swift
//  SyncBoard
//

import Foundation
import Observation

/// Orchestrates Google Drive sync: owns the auth manager, drives the Drive
/// REST calls, and exposes the state the UI needs (connected account,
/// syncing spinner, last error). `ClipboardManager` calls `scheduleSync()`
/// whenever local history changes; this debounces that into a single sync.
@MainActor
@Observable
final class GoogleDriveSyncManager {
    static let shared = GoogleDriveSyncManager()

    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?

    var isConnected: Bool { auth.isConnected }
    var accountEmail: String? { auth.accountEmail }

    private let auth = GoogleDriveAuthManager.shared
    private var debouncedSyncTask: Task<Void, Never>?
    private var periodicTimer: Timer?

    private init() {}

    /// Call once at launch. Syncs immediately if already connected, then
    /// keeps pulling changes from other Macs every few minutes.
    func startPeriodicSync() {
        guard periodicTimer == nil else { return }
        if isConnected {
            syncNow()
        }
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.syncNow() }
        }
    }

    func connect() async {
        lastError = nil
        do {
            try await auth.connect()
            syncNow()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        auth.disconnect()
        lastSyncedAt = nil
        lastError = nil
    }

    func dismissError() {
        lastError = nil
    }

    /// Coalesces rapid-fire local changes (several clipboard copies/deletes
    /// in a row) into a single sync a moment later instead of one per change.
    func scheduleSync() {
        guard isConnected else { return }
        debouncedSyncTask?.cancel()
        debouncedSyncTask = Task { [weak self] in
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
                let accessToken = try await auth.validAccessToken()
                let service = GoogleDriveSyncService(accessToken: accessToken)
                let merged = try await service.sync(localHistory: ClipboardManager.shared.history)
                ClipboardManager.shared.replaceHistory(with: merged)
                lastSyncedAt = Date()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
