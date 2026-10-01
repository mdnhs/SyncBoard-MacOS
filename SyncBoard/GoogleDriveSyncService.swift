//
//  GoogleDriveSyncService.swift
//  SyncBoard
//

import Foundation

enum GoogleDriveSyncError: LocalizedError {
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code, let message):
            return "Google Drive request failed (\(code)): \(message)"
        }
    }
}

/// Talks to the Drive v3 REST API directly (no SDK dependency, since this
/// is the only Drive feature the app needs) to keep a single JSON file —
/// the full clipboard history — inside the app's hidden `appDataFolder`
/// space, and merges it with whatever's stored locally.
struct GoogleDriveSyncService {
    private let fileName = "syncboard_history.json"
    private let accessToken: String

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    /// Downloads the remote history (creating the remote file first if this
    /// is the first sync), unions it with the local history by item id, and
    /// writes the merged result back. Deleting an item locally does not yet
    /// delete it on other Macs — merging is additive only.
    func sync(localHistory: [ClipboardItem]) async throws -> [ClipboardItem] {
        let fileID = try await findOrCreateFileID()
        let remoteHistory = try await downloadHistory(fileID: fileID)
        let merged = Self.merge(local: localHistory, remote: remoteHistory)
        try await uploadHistory(merged, fileID: fileID)
        return merged
    }

    static func merge(local: [ClipboardItem], remote: [ClipboardItem]) -> [ClipboardItem] {
        var byID: [UUID: ClipboardItem] = [:]
        for item in remote { byID[item.id] = item }
        for item in local { byID[item.id] = item }
        return byID.values.sorted { $0.date > $1.date }
    }

    // MARK: - Drive API

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
            URLQueryItem(name: "q", value: "name='\(fileName)'"),
            URLQueryItem(name: "fields", value: "files(id)")
        ]
        struct FileList: Decodable {
            struct File: Decodable { let id: String }
            let files: [File]
        }
        let list: FileList = try await get(components.url!)
        return list.files.first?.id
    }

    private func createEmptyFile() async throws -> String {
        let metadata = ["name": fileName, "parents": ["appDataFolder"]] as [String: Any]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let boundary = "SyncBoard-\(UUID().uuidString)"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append("[]".data(using: .utf8)!)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)
        request.httpBody = body

        struct CreatedFile: Decodable { let id: String }
        let created: CreatedFile = try await send(request)
        return created.id
    }

    private func downloadHistory(fileID: String) async throws -> [ClipboardItem] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ClipboardItem].self, from: data)) ?? []
    }

    private func uploadHistory(_ history: [ClipboardItem], fileID: String) async throws {
        let data = try JSONEncoder().encode(history)
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: responseData)
    }

    // MARK: - Helpers

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleDriveSyncError.requestFailed(http.statusCode, message)
        }
    }
}
