//
//  GoogleDriveSyncService.swift
//  SyncBoard
//

import Foundation

/// Merge rules for the clipboard history file. Drive I/O lives in
/// `GoogleDriveJSONFile`.
enum GoogleDriveSyncService {
    static let fileName = "syncboard_history.json"

    static func merge(local: [ClipboardItem], remote: [ClipboardItem]) -> [ClipboardItem] {
        var byID: [String: ClipboardItem] = [:]
        for item in remote { byID[item.id] = item }
        for item in local { byID[item.id] = item }
        return byID.values.sorted { $0.date > $1.date }
    }
}

// MARK: - Errors

nonisolated enum SyncError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response received from Google Drive."
        case .httpError(let statusCode):
            return "Google Drive API error (HTTP \(statusCode))."
        }
    }
}
