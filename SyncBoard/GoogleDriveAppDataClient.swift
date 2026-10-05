//
//  GoogleDriveAppDataClient.swift
//  SyncBoard
//

import Foundation

/// Identity of a JSON file in `appDataFolder`. Drive bumps `version` on every
/// write, so an unchanged version means the cached contents are still current.
nonisolated struct DriveAppDataFile: Codable, Sendable, Equatable {
    let id: String
    let version: String
}

/// Thin wrapper over the Drive v3 endpoints SyncBoard needs for its
/// `appDataFolder` JSON files.
nonisolated struct GoogleDriveAppDataClient: Sendable {
    private let authManager: GoogleDriveAuthManager

    init(authManager: GoogleDriveAuthManager) {
        self.authManager = authManager
    }

    /// Lists every SyncBoard file in one request, keyed by file name.
    func listFiles() async throws -> [String: DriveAppDataFile] {
        try await queryFiles(matching: "trashed = false")
    }

    func file(named name: String) async throws -> DriveAppDataFile? {
        try await queryFiles(matching: "name = '\(name)' and trashed = false")[name]
    }

    func download(_ file: DriveAppDataFile) async throws -> Data {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!
        return try await perform(URLRequest(url: url))
    }

    func update(_ file: DriveAppDataFile, with data: Data) async throws -> DriveAppDataFile {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(file.id)?uploadType=media&fields=id,version")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return try JSONDecoder().decode(DriveAppDataFile.self, from: try await perform(request))
    }

    func create(named name: String, with data: Data) async throws -> DriveAppDataFile {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,version")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "SyncBoard-\(UUID().uuidString)"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadataJSON = """
        {"name": "\(name)", "parents": ["appDataFolder"]}
        """
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n\(metadataJSON)\r\n".utf8))
        body.append(Data("--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        return try JSONDecoder().decode(DriveAppDataFile.self, from: try await perform(request))
    }

    // MARK: - Helpers

    private func queryFiles(matching query: String) async throws -> [String: DriveAppDataFile] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name, version)"),
            URLQueryItem(name: "orderBy", value: "createdTime"),
            URLQueryItem(name: "pageSize", value: "100"),
        ]
        let data = try await perform(URLRequest(url: components.url!))
        let response = try JSONDecoder().decode(FileListResponse.self, from: data)
        // Oldest wins if a race ever produced duplicates, so every device picks the same file.
        return response.files.reduce(into: [:]) { result, file in
            if result[file.name] == nil {
                result[file.name] = DriveAppDataFile(id: file.id, version: file.version)
            }
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
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

    private struct FileListResponse: Decodable {
        let files: [Entry]

        struct Entry: Decodable {
            let id: String
            let name: String
            let version: String
        }
    }
}

/// One JSON array file in `appDataFolder`. Remembers the last contents it saw
/// so an unchanged remote version skips the download, and an unchanged result
/// skips the upload. Main-actor bound because the synced models' `Codable`
/// conformances are.
final class GoogleDriveJSONFile<Item: Codable & Equatable & Identifiable> where Item.ID == String {
    private let name: String
    private let client: GoogleDriveAppDataClient
    private var snapshot: (file: DriveAppDataFile, items: [Item])?

    init(name: String, client: GoogleDriveAppDataClient) {
        self.name = name
        self.client = client
    }

    func metadata() async throws -> DriveAppDataFile? {
        try await client.file(named: name)
    }

    func read(remote: DriveAppDataFile?) async throws -> [Item] {
        guard let remote else { return [] }
        if let snapshot, snapshot.file == remote {
            return snapshot.items
        }
        let data = try await client.download(remote)
        let items = data.isEmpty ? [] : try JSONDecoder().decode([Item].self, from: data)
        snapshot = (remote, items)
        return items
    }

    /// Applies `transform` to the remote contents and uploads the result only
    /// if it actually differs from what Drive already has.
    func update(remote: DriveAppDataFile?, _ transform: ([Item]) -> [Item]) async throws -> [Item] {
        let current = try await read(remote: remote)
        let updated = transform(current)

        if let remote {
            guard !Self.hasSameContents(updated, current) else { return updated }
            let data = try JSONEncoder().encode(updated)
            snapshot = (try await client.update(remote, with: data), updated)
        } else {
            guard !updated.isEmpty else { return updated }
            let data = try JSONEncoder().encode(updated)
            snapshot = (try await client.create(named: name, with: data), updated)
        }
        return updated
    }

    /// Order-insensitive because merges sort by fields that can tie.
    private static func hasSameContents(_ lhs: [Item], _ rhs: [Item]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let rhsByID = Dictionary(rhs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return lhs.allSatisfy { rhsByID[$0.id] == $0 }
    }
}
