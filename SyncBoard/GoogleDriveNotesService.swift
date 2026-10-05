//
//  GoogleDriveNotesService.swift
//  SyncBoard
//

import Foundation

/// Merge rules for the Quick Notes file. Drive I/O lives in
/// `GoogleDriveJSONFile`.
enum GoogleDriveNotesService {
    static let fileName = "syncboard_notes.json"

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
}
