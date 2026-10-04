//
//  TodoManager.swift
//  SyncBoard
//

import Foundation
import Observation

@MainActor
@Observable
final class TodoManager {
    static let shared = TodoManager()

    private(set) var items: [TodoItem] = []

    private let storageKey = "com.nazmulhsourab.SyncBoard.todoItems"

    private init() {
        loadItems()
    }

    @discardableResult
    func createItem(title: String = "", status: TodoStatus = .todo) -> TodoItem {
        let item = TodoItem(title: title, status: status)
        items.insert(item, at: 0)
        saveAndSync()
        return item
    }

    func updateContent(_ item: TodoItem, title: String, notes: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index].title != title || items[index].notes != notes else { return }
        items[index].title = title
        items[index].notes = notes
        items[index].updatedAt = Date()
        saveAndSync()
    }

    func moveStatus(_ item: TodoItem, to status: TodoStatus) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index].status != status else { return }
        items[index].status = status
        items[index].updatedAt = Date()
        saveAndSync()
    }

    func setColor(_ item: TodoItem, color: NoteColor) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index].color != color else { return }
        items[index].color = color
        items[index].updatedAt = Date()
        saveAndSync()
    }

    func setTheme(_ item: TodoItem, theme: NoteTheme) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index].theme != theme || items[index].customThemeId != nil else { return }
        items[index].theme = theme
        items[index].customThemeId = nil
        items[index].updatedAt = Date()
        saveAndSync()
    }

    func setCustomTheme(_ item: TodoItem, customThemeId: String?) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index].customThemeId != customThemeId else { return }
        items[index].customThemeId = customThemeId
        items[index].theme = .none
        items[index].updatedAt = Date()
        saveAndSync()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        saveAndSync()
    }

    /// Replaces local items with the result of a Google Drive merge.
    func replaceItems(with items: [TodoItem]) {
        self.items = items.sorted { $0.updatedAt > $1.updatedAt }
        saveItems()
    }

    private func saveAndSync() {
        saveItems()
        GoogleDriveSyncManager.shared.scheduleSync()
    }

    private func saveItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        items = decoded
    }
}
