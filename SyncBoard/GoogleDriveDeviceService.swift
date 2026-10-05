//
//  GoogleDriveDeviceService.swift
//  SyncBoard
//

import Foundation

/// Persists the shared "which devices are signed in" registry as a JSON file
/// in the account's `appDataFolder`, alongside the clipboard history file.
struct GoogleDriveDeviceService {
    static let fileName = "syncboard_devices.json"

    /// Without this every debounced sync would rewrite the registry just to bump `lastSeenAt`.
    private static let heartbeatInterval: TimeInterval = 4 * 60

    private let file: GoogleDriveJSONFile<DeviceSession>

    init(client: GoogleDriveAppDataClient) {
        file = GoogleDriveJSONFile(name: Self.fileName, client: client)
    }

    // MARK: - Public API

    func fetchDevices() async throws -> [DeviceSession] {
        try await file.read(remote: file.metadata())
    }

    /// Adds or refreshes this device's entry and uploads the merged list.
    /// If the registry already has entries and this device isn't one of
    /// them, another device explicitly signed it out — leave it absent
    /// rather than silently re-adding it.
    func heartbeatCurrentDevice(remote: DriveAppDataFile?) async throws -> [DeviceSession] {
        try await file.update(remote: remote) { devices in
            let isStillRegistered = devices.contains { $0.id == DeviceIdentity.currentID }
            guard isStillRegistered || devices.isEmpty else { return devices }
            return Self.upsertCurrentDevice(into: devices, force: false)
        }
    }

    /// Unconditionally (re)registers this device, used right after connecting.
    func registerCurrentDevice() async throws -> [DeviceSession] {
        try await file.update(remote: file.metadata()) { devices in
            Self.upsertCurrentDevice(into: devices, force: true)
        }
    }

    func removeDevice(id: String) async throws -> [DeviceSession] {
        try await file.update(remote: file.metadata()) { devices in
            devices.filter { $0.id != id }
        }
    }

    // MARK: - Helpers

    private static func upsertCurrentDevice(into devices: [DeviceSession], force: Bool) -> [DeviceSession] {
        var updated = devices
        let now = Date()
        if let index = updated.firstIndex(where: { $0.id == DeviceIdentity.currentID }) {
            let existing = updated[index]
            let isFresh = existing.name == DeviceIdentity.currentName
                && existing.osVersion == DeviceIdentity.osVersion
                && now.timeIntervalSince(existing.lastSeenAt) < heartbeatInterval
            guard force || !isFresh else { return devices }
            updated[index].name = DeviceIdentity.currentName
            updated[index].osVersion = DeviceIdentity.osVersion
            updated[index].lastSeenAt = now
        } else {
            updated.append(
                DeviceSession(
                    id: DeviceIdentity.currentID,
                    name: DeviceIdentity.currentName,
                    osName: DeviceIdentity.osName,
                    osVersion: DeviceIdentity.osVersion,
                    loginDate: now,
                    lastSeenAt: now
                )
            )
        }
        return updated
    }
}
