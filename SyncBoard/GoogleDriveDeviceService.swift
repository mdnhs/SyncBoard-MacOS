//
//  GoogleDriveDeviceService.swift
//  SyncBoard
//

import Foundation

/// Persists the shared "which devices are signed in" registry as a second
/// JSON file in the account's `appDataFolder`, alongside the clipboard
/// history file. Mirrors `GoogleDriveSyncService`'s Drive plumbing since both
/// need the same find-or-create/download/upload flow against a single file.
actor GoogleDriveDeviceService {
    private let authManager: GoogleDriveAuthManager
    private let fileName = "syncboard_devices.json"
    private var cachedFileID: String?

    init(authManager: GoogleDriveAuthManager = .shared) {
        self.authManager = authManager
    }

    // MARK: - Public API

    func fetchDevices() async throws -> [DeviceSession] {
        guard let fileID = try await findFileID() else { return [] }
        return try await downloadDevices(fileID: fileID)
    }

    /// Adds or refreshes this device's entry and uploads the merged list.
    /// If the registry already has entries and this device isn't one of
    /// them, another device explicitly signed it out — leave it absent
    /// rather than silently re-adding it.
    func heartbeatCurrentDevice() async throws -> [DeviceSession] {
        let fileID = try await findOrCreateFileID()
        let devices = try await downloadDevices(fileID: fileID)
        let isStillRegistered = devices.contains { $0.id == DeviceIdentity.currentID }
        guard isStillRegistered || devices.isEmpty else {
            return devices
        }
        return try await upsertCurrentDevice(into: devices, fileID: fileID)
    }

    /// Unconditionally (re)registers this device, used right after connecting.
    func registerCurrentDevice() async throws -> [DeviceSession] {
        let fileID = try await findOrCreateFileID()
        let devices = try await downloadDevices(fileID: fileID)
        return try await upsertCurrentDevice(into: devices, fileID: fileID)
    }

    func removeDevice(id: String) async throws -> [DeviceSession] {
        let fileID = try await findOrCreateFileID()
        var devices = try await downloadDevices(fileID: fileID)
        devices.removeAll { $0.id == id }
        try await uploadDevices(devices, fileID: fileID)
        return devices
    }

    // MARK: - Helpers

    private func upsertCurrentDevice(into devices: [DeviceSession], fileID: String) async throws -> [DeviceSession] {
        var updated = devices
        let now = Date()
        if let index = updated.firstIndex(where: { $0.id == DeviceIdentity.currentID }) {
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
        try await uploadDevices(updated, fileID: fileID)
        return updated
    }

    // MARK: - Drive API (find/create/download/upload a single JSON file)

    private func findOrCreateFileID() async throws -> String {
        if let existing = try await findFileID() {
            return existing
        }
        return try await createEmptyFile()
    }

    private func findFileID() async throws -> String? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "name = '\(fileName)' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id, name)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let data = try await performAuthorizedRequest(request)
        let response = try JSONDecoder().decode(DriveFileListResponse.self, from: data)
        let fileID = response.files.first?.id
        cachedFileID = fileID
        return fileID
    }

    private func createEmptyFile() async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        let boundary = "SyncBoard-\(UUID().uuidString)"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadataJSON = """
        {"name": "\(fileName)", "parents": ["appDataFolder"]}
        """
        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n\(metadataJSON)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Type: application/json\r\n\r\n[]\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data = try await performAuthorizedRequest(request)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)
        cachedFileID = file.id
        return file.id
    }

    private func downloadDevices(fileID: String) async throws -> [DeviceSession] {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await performAuthorizedRequest(request)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([DeviceSession].self, from: data)
    }

    private func uploadDevices(_ devices: [DeviceSession], fileID: String) async throws {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(devices)
        _ = try await performAuthorizedRequest(request)
    }

    private func performAuthorizedRequest(_ request: URLRequest) async throws -> Data {
        let token = try await authManager.validAccessToken()
        var authedRequest = request
        authedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: authedRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw SyncError.httpError(statusCode: http.statusCode)
        }
        return data
    }
}

// MARK: - Models

private struct DriveFileListResponse: Codable {
    let files: [DriveFile]
}

private struct DriveFile: Codable {
    let id: String
    let name: String
}
