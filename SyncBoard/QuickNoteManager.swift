//
//  QuickNoteManager.swift
//  SyncBoard
//

import Foundation
import Observation

@MainActor
@Observable
final class QuickNoteManager {
    static let shared = QuickNoteManager()

    /// Live notes plus deletion tombstones; only `notes` is shown in the UI.
    private(set) var syncNotes: [QuickNote] = []

    var notes: [QuickNote] { syncNotes.filter { $0.deletedAt == nil } }

    private let storageKey = "com.nazmulhsourab.SyncBoard.quickNotes"
    private let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    private init() {
        loadNotes()
    }

    @discardableResult
    func createNote(title: String = "", text: String = "") -> QuickNote {
        let note = QuickNote(title: title, text: text, kind: .text, sortOrder: topSortOrder, positionUpdatedAt: Date())
        syncNotes.insert(note, at: 0)
        saveAndSync()
        return note
    }

    @discardableResult
    func createChecklistNote(title: String = "") -> QuickNote {
        let note = QuickNote(title: title, checklistItems: [ChecklistItem()], kind: .checklist, sortOrder: topSortOrder, positionUpdatedAt: Date())
        syncNotes.insert(note, at: 0)
        saveAndSync()
        return note
    }

    func updateContent(_ note: QuickNote, title: String, text: String) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }) else { return }
        guard syncNotes[index].title != title || syncNotes[index].text != text else { return }
        syncNotes[index].title = title
        syncNotes[index].text = text
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    func updateChecklist(_ note: QuickNote, title: String, items: [ChecklistItem]) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }) else { return }
        guard syncNotes[index].title != title || syncNotes[index].checklistItems != items else { return }
        syncNotes[index].title = title
        syncNotes[index].checklistItems = items
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    /// Splits an existing text note's lines into checklist rows and flips
    /// its kind — matching how Google Keep offers to turn a note into a checklist.
    func convertToChecklist(_ note: QuickNote) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }), syncNotes[index].kind == .text else { return }
        let lines = syncNotes[index].text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        syncNotes[index].checklistItems = lines.isEmpty ? [ChecklistItem()] : lines.map { ChecklistItem(text: $0) }
        syncNotes[index].kind = .checklist
        syncNotes[index].text = ""
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    /// Converts checklist items back into lines of text.
    func convertToText(_ note: QuickNote) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }), syncNotes[index].kind == .checklist else { return }
        let text = syncNotes[index].checklistItems.map { $0.text }.joined(separator: "\n")
        syncNotes[index].text = text
        syncNotes[index].kind = .text
        syncNotes[index].checklistItems = []
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    func togglePin(_ note: QuickNote) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }) else { return }
        syncNotes[index].isPinned.toggle()
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    func setColor(_ note: QuickNote, color: NoteColor) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }) else { return }
        syncNotes[index].color = color
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    func setTheme(_ note: QuickNote, theme: NoteTheme) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }) else { return }
        syncNotes[index].theme = theme
        syncNotes[index].customThemeId = nil
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    func setCustomTheme(_ note: QuickNote, customThemeId: String?) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }) else { return }
        syncNotes[index].customThemeId = customThemeId
        syncNotes[index].theme = .none
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    func setArchived(_ note: QuickNote, isArchived: Bool) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }) else { return }
        syncNotes[index].isArchived = isArchived
        syncNotes[index].updatedAt = Date()
        saveAndSync()
    }

    func delete(_ note: QuickNote) {
        guard let index = syncNotes.firstIndex(where: { $0.id == note.id }),
              syncNotes[index].deletedAt == nil else { return }
        let now = Date()
        syncNotes[index].deletedAt = now
        syncNotes[index].updatedAt = now
        saveAndSync()
    }

    private var topSortOrder: Double {
        (syncNotes.map(\.sortOrder).min() ?? 0) - 1
    }

    /// Live Keep-style reorder: swaps the two notes' board positions in memory
    /// only, so no other card changes column. Call `commitReorder()` when the drag ends.
    func swap(_ draggedID: String, with targetID: String) {
        guard draggedID != targetID,
              let from = syncNotes.firstIndex(where: { $0.id == draggedID }),
              let to = syncNotes.firstIndex(where: { $0.id == targetID }) else { return }
        let now = Date()
        let draggedOrder = syncNotes[from].sortOrder
        syncNotes[from].sortOrder = syncNotes[to].sortOrder
        syncNotes[to].sortOrder = draggedOrder
        syncNotes[from].positionUpdatedAt = now
        syncNotes[to].positionUpdatedAt = now
        syncNotes.swapAt(from, to)
    }

    func commitReorder() {
        saveAndSync()
    }

    /// Replaces local notes with the result of a Google Drive merge.
    func replaceNotes(with items: [QuickNote]) {
        let cutoff = Date().addingTimeInterval(-tombstoneLifetime)
        syncNotes = items
            .filter { ($0.deletedAt ?? .distantFuture) > cutoff }
            .sorted { $0.sortOrder < $1.sortOrder }
        saveNotes()
    }

    private func saveAndSync() {
        saveNotes()
        GoogleDriveSyncManager.shared.scheduleSync()
    }

    private func saveNotes() {
        guard let data = try? JSONEncoder().encode(syncNotes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadNotes() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([QuickNote].self, from: data) else { return }
        syncNotes = decoded.sorted { $0.sortOrder < $1.sortOrder }
    }
}
