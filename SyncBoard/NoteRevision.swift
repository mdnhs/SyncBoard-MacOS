//
//  NoteRevision.swift
//  SyncBoard
//

import Foundation

/// A synced snapshot of a note's content, recorded whenever a sync uploads a
/// content change. Pin, color, and position changes don't create revisions.
struct NoteRevision: Identifiable, Codable, Equatable {
    let id: String
    let noteID: String
    var title: String
    var text: String
    var checklistItems: [ChecklistItem]
    var kind: QuickNoteKind
    let createdAt: Date
    /// Later than `createdAt` when follow-up syncs were folded into this revision.
    var savedAt: Date
    /// The device whose sync uploaded this revision.
    var origin: DeviceOrigin?

    init(note: QuickNote, savedAt: Date = Date(), origin: DeviceOrigin? = .current) {
        id = ULID.generate()
        noteID = note.id
        title = note.title
        text = note.text
        checklistItems = note.checklistItems
        kind = note.kind
        createdAt = savedAt
        self.savedAt = savedAt
        self.origin = origin
    }

    func hasSameContent(as note: QuickNote) -> Bool {
        title == note.title && text == note.text && checklistItems == note.checklistItems && kind == note.kind
    }
}
