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

    /// Live tasks plus deletion tombstones; only `items` is shown in the UI.
    private(set) var syncItems: [TodoItem] = []

    var items: [TodoItem] { syncItems.filter { $0.deletedAt == nil } }

    private let storageKey = "com.nazmulhsourab.SyncBoard.todoItems"
    private let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    private init() {
        loadItems()
    }

    @discardableResult
    func createItem(title: String = "", status: TodoStatus = .todo) -> TodoItem {
        let item = TodoItem(title: title, status: status)
        syncItems.insert(item, at: 0)
        saveAndSync()
        return item
    }

    func updateContent(_ item: TodoItem, title: String, notes: String) {
        guard let index = syncItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard syncItems[index].title != title || syncItems[index].notes != notes else { return }
        syncItems[index].title = title
        syncItems[index].notes = notes
        syncItems[index].updatedAt = Date()
        saveAndSync()
    }

    func moveStatus(_ item: TodoItem, to status: TodoStatus) {
        guard let index = syncItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard syncItems[index].status != status else { return }
        syncItems[index].status = status
        syncItems[index].updatedAt = Date()
        saveAndSync()
    }

    func setColor(_ item: TodoItem, color: NoteColor) {
        guard let index = syncItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard syncItems[index].color != color else { return }
        syncItems[index].color = color
        syncItems[index].updatedAt = Date()
        saveAndSync()
    }

    func setTheme(_ item: TodoItem, theme: NoteTheme) {
        guard let index = syncItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard syncItems[index].theme != theme || syncItems[index].customThemeId != nil else { return }
        syncItems[index].theme = theme
        syncItems[index].customThemeId = nil
        syncItems[index].updatedAt = Date()
        saveAndSync()
    }

    func setCustomTheme(_ item: TodoItem, customThemeId: String?) {
        guard let index = syncItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard syncItems[index].customThemeId != customThemeId else { return }
        syncItems[index].customThemeId = customThemeId
        syncItems[index].theme = .none
        syncItems[index].updatedAt = Date()
        saveAndSync()
    }

    func delete(_ item: TodoItem) {
        guard let index = syncItems.firstIndex(where: { $0.id == item.id }),
              syncItems[index].deletedAt == nil else { return }
        let now = Date()
        syncItems[index].deletedAt = now
        syncItems[index].updatedAt = now
        saveAndSync()
    }

    /// Replaces local items with the result of a Google Drive merge.
    func replaceItems(with items: [TodoItem]) {
        let cutoff = Date().addingTimeInterval(-tombstoneLifetime)
        let latest = items
            .filter { ($0.deletedAt ?? .distantFuture) > cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard latest != syncItems else { return }
        syncItems = latest
        saveItems()
    }

    private func saveAndSync() {
        saveItems()
        GoogleDriveSyncManager.shared.scheduleSync()
    }

    private func saveItems() {
        guard let data = try? JSONEncoder().encode(syncItems) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        syncItems = decoded
    }
}
