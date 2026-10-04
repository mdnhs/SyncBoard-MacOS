//
//  GoogleDriveNotesService.swift
//  SyncBoard
//

import Foundation

/// Persists Quick Notes as a JSON file in the account's `appDataFolder`,
/// alongside the clipboard history, device registry, and To Do files.
/// Mirrors `GoogleDriveSyncService`'s Drive plumbing.
actor GoogleDriveNotesService {
    private let authManager: GoogleDriveAuthManager
    private let fileName = "syncboard_notes.json"
    private var cachedFileID: String?

    init(authManager: GoogleDriveAuthManager = .shared) {
        self.authManager = authManager
    }

    // MARK: - Public API

    func fetchNotes() async throws -> [QuickNote] {
        guard let fileID = try await findFileID() else { return [] }
        return try await downloadNotes(fileID: fileID)
    }

    func sync(localNotes: [QuickNote]) async throws -> [QuickNote] {
        let fileID = try await findOrCreateFileID()
        let remoteNotes = try await downloadNotes(fileID: fileID)
        let merged = Self.merge(local: localNotes, remote: remoteNotes)
        try await uploadNotes(merged, fileID: fileID)
        return merged
    }

    /// Notes are edited in place (unlike clipboard entries, which are only
    /// appended or deleted), so the merge keeps whichever copy of each note
    /// was updated most recently instead of always preferring the local one.
    /// Board position is merged on its own timestamp so a reorder on one
    /// device and a content edit on another both survive.
    static func merge(local: [QuickNote], remote: [QuickNote]) -> [QuickNote] {
        var byID: [String: QuickNote] = [:]
        for note in remote { byID[note.id] = note }
        for note in local {
            guard let existing = byID[note.id] else {
                byID[note.id] = note
                continue
            }
            var winner = existing.updatedAt > note.updatedAt ? existing : note
            let positionSource = existing.positionUpdatedAt > note.positionUpdatedAt ? existing : note
            winner.sortOrder = positionSource.sortOrder
            winner.positionUpdatedAt = positionSource.positionUpdatedAt
            byID[note.id] = winner
        }
        return byID.values.sorted { $0.sortOrder < $1.sortOrder }
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

    private func downloadNotes(fileID: String) async throws -> [QuickNote] {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await performAuthorizedRequest(request)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([QuickNote].self, from: data)
    }

    private func uploadNotes(_ notes: [QuickNote], fileID: String) async throws {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(notes)
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
