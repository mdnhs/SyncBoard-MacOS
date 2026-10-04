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

    private(set) var notes: [QuickNote] = []

    private let storageKey = "com.nazmulhsourab.SyncBoard.quickNotes"

    private init() {
        loadNotes()
    }

    @discardableResult
    func createNote(title: String = "", text: String = "") -> QuickNote {
        let note = QuickNote(title: title, text: text, kind: .text)
        notes.insert(note, at: 0)
        saveAndSync()
        return note
    }

    @discardableResult
    func createChecklistNote(title: String = "") -> QuickNote {
        let note = QuickNote(title: title, checklistItems: [ChecklistItem()], kind: .checklist)
        notes.insert(note, at: 0)
        saveAndSync()
        return note
    }

    func updateContent(_ note: QuickNote, title: String, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        guard notes[index].title != title || notes[index].text != text else { return }
        notes[index].title = title
        notes[index].text = text
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    func updateChecklist(_ note: QuickNote, title: String, items: [ChecklistItem]) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        guard notes[index].title != title || notes[index].checklistItems != items else { return }
        notes[index].title = title
        notes[index].checklistItems = items
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    /// Splits an existing text note's lines into checklist rows and flips
    /// its kind — matching how Google Keep offers to turn a note into a checklist.
    func convertToChecklist(_ note: QuickNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }), notes[index].kind == .text else { return }
        let lines = notes[index].text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        notes[index].checklistItems = lines.isEmpty ? [ChecklistItem()] : lines.map { ChecklistItem(text: $0) }
        notes[index].kind = .checklist
        notes[index].text = ""
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    /// Converts checklist items back into lines of text.
    func convertToText(_ note: QuickNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }), notes[index].kind == .checklist else { return }
        let text = notes[index].checklistItems.map { $0.text }.joined(separator: "\n")
        notes[index].text = text
        notes[index].kind = .text
        notes[index].checklistItems = []
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    func togglePin(_ note: QuickNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isPinned.toggle()
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    func setColor(_ note: QuickNote, color: NoteColor) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].color = color
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    func setTheme(_ note: QuickNote, theme: NoteTheme) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].theme = theme
        notes[index].customThemeId = nil
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    func setCustomTheme(_ note: QuickNote, customThemeId: String?) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].customThemeId = customThemeId
        notes[index].theme = .none
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    func setArchived(_ note: QuickNote, isArchived: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isArchived = isArchived
        notes[index].updatedAt = Date()
        saveAndSync()
    }

    func delete(_ note: QuickNote) {
        notes.removeAll { $0.id == note.id }
        saveAndSync()
    }

    /// Replaces local notes with the result of a Google Drive merge.
    func replaceNotes(with items: [QuickNote]) {
        notes = items.sorted { $0.updatedAt > $1.updatedAt }
        saveNotes()
    }

    private func saveAndSync() {
        saveNotes()
        GoogleDriveSyncManager.shared.scheduleSync()
    }

    private func saveNotes() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadNotes() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([QuickNote].self, from: data) else { return }
        notes = decoded
    }
}
