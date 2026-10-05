//
//  GoogleDriveNoteHistoryService.swift
//  SyncBoard
//

import Foundation

/// Rules for the note revision history file. Drive I/O lives in
/// `GoogleDriveJSONFile`.
enum GoogleDriveNoteHistoryService {
    static let fileName = "syncboard_note_history.json"

    /// Consecutive syncs from one device inside this window update a single
    /// revision, so a typing session doesn't produce one entry per debounce.
    private static let coalesceWindow: TimeInterval = 10 * 60
    static let maxRevisionsPerNote = 30

    /// Notes whose content differs from what Drive held before this sync.
    static func contentChanges(in merged: [QuickNote], comparedTo remote: [QuickNote]) -> [QuickNote] {
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return merged.filter { note in
            guard note.deletedAt == nil, !isEmpty(note) else { return false }
            guard let previous = remoteByID[note.id] else { return true }
            return previous.title != note.title
                || previous.text != note.text
                || previous.checklistItems != note.checklistItems
                || previous.kind != note.kind
        }
    }

    static func record(_ notes: [QuickNote], into revisions: [NoteRevision], at now: Date = Date()) -> [NoteRevision] {
        var result = revisions
        for note in notes {
            let latestIndex = result.indices
                .filter { result[$0].noteID == note.id }
                .max { result[$0].savedAt < result[$1].savedAt }

            if let latestIndex {
                let latest = result[latestIndex]
                if latest.hasSameContent(as: note) { continue }
                if latest.origin?.isCurrentDevice == true, now.timeIntervalSince(latest.createdAt) < coalesceWindow {
                    result[latestIndex].title = note.title
                    result[latestIndex].text = note.text
                    result[latestIndex].checklistItems = note.checklistItems
                    result[latestIndex].kind = note.kind
                    result[latestIndex].savedAt = now
                    continue
                }
            }
            result.append(NoteRevision(note: note, savedAt: now))
        }
        return pruned(result)
    }

    private static func pruned(_ revisions: [NoteRevision]) -> [NoteRevision] {
        Dictionary(grouping: revisions, by: \.noteID).values
            .flatMap { $0.sorted { $0.savedAt > $1.savedAt }.prefix(maxRevisionsPerNote) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    private static func isEmpty(_ note: QuickNote) -> Bool {
        note.title.isEmpty
            && note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.checklistItems.allSatisfy { $0.text.isEmpty }
    }
}
