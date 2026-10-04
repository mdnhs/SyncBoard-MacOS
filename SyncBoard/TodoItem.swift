//
//  TodoItem.swift
//  SyncBoard
//

import SwiftUI

/// A Kanban column. Order here is the display order left-to-right.
enum TodoStatus: String, CaseIterable, Codable, Identifiable {
    case todo = "To Do"
    case inProgress = "In Progress"
    case done = "Done"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .todo: return .secondary
        case .inProgress: return .orange
        case .done: return .green
        }
    }
}

/// A single Kanban task card. There's no attachment affordance anywhere in
/// the UI, so media never enters this model — just a title and notes.
struct TodoItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var title: String
    var notes: String
    var status: TodoStatus
    var color: NoteColor
    var theme: NoteTheme
    var customThemeId: String?
    let createdAt: Date
    var updatedAt: Date
    /// Tombstone: kept and synced so the Drive merge can't resurrect a deleted task.
    var deletedAt: Date?

    var isSensitive: Bool {
        guard AppSettings.shared.maskSensitiveContent else { return false }
        return SensitiveContentDetector.looksSensitive(title) || SensitiveContentDetector.looksSensitive(notes)
    }

    init(
        id: String = ULID.generate(),
        title: String = "",
        notes: String = "",
        status: TodoStatus = .todo,
        color: NoteColor = .default,
        theme: NoteTheme = .none,
        customThemeId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.color = color
        self.theme = theme
        self.customThemeId = customThemeId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, status, color, theme, customThemeId, createdAt, updatedAt, deletedAt
    }

    // Custom decoding for backward compatibility with tasks saved before color/theme existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        status = try container.decodeIfPresent(TodoStatus.self, forKey: .status) ?? .todo
        color = try container.decodeIfPresent(NoteColor.self, forKey: .color) ?? .default
        theme = try container.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .none
        customThemeId = try container.decodeIfPresent(String.self, forKey: .customThemeId)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
