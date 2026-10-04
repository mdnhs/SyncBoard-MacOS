//
//  GoogleDriveTodoService.swift
//  SyncBoard
//

import Foundation

/// Persists the To Do Kanban board as a third JSON file in the account's
/// `appDataFolder`, alongside the clipboard history and device registry
/// files. Mirrors `GoogleDriveSyncService`'s Drive plumbing.
actor GoogleDriveTodoService {
    private let authManager: GoogleDriveAuthManager
    private let fileName = "syncboard_todos.json"
    private var cachedFileID: String?

    init(authManager: GoogleDriveAuthManager = .shared) {
        self.authManager = authManager
    }

    // MARK: - Public API

    func fetchItems() async throws -> [TodoItem] {
        guard let fileID = try await findFileID() else { return [] }
        return try await downloadItems(fileID: fileID)
    }

    func sync(localItems: [TodoItem]) async throws -> [TodoItem] {
        let fileID = try await findOrCreateFileID()
        let remoteItems = try await downloadItems(fileID: fileID)
        let merged = Self.merge(local: localItems, remote: remoteItems)
        try await uploadItems(merged, fileID: fileID)
        return merged
    }

    /// Tasks are edited and moved between columns in place (unlike clipboard
    /// entries, which are only appended or deleted), so the merge keeps
    /// whichever copy of each task was updated most recently instead of
    /// always preferring the local one.
    static func merge(local: [TodoItem], remote: [TodoItem]) -> [TodoItem] {
        var byID: [String: TodoItem] = [:]
        for item in remote { byID[item.id] = item }
        for item in local {
            if let existing = byID[item.id], existing.updatedAt > item.updatedAt {
                continue
            }
            byID[item.id] = item
        }
        return byID.values.sorted { $0.updatedAt > $1.updatedAt }
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

    private func downloadItems(fileID: String) async throws -> [TodoItem] {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await performAuthorizedRequest(request)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([TodoItem].self, from: data)
    }

    private func uploadItems(_ items: [TodoItem], fileID: String) async throws {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(items)
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
