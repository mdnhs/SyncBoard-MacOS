//
//  GoogleDriveTodoService.swift
//  SyncBoard
//

import Foundation

/// Merge rules for the To Do Kanban board file. Drive I/O lives in
/// `GoogleDriveJSONFile`.
enum GoogleDriveTodoService {
    static let fileName = "syncboard_todos.json"

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
}
