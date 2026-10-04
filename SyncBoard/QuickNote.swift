//
//  QuickNote.swift
//  SyncBoard
//

import SwiftUI

/// A single row in a checklist-style note.
struct ChecklistItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var text: String
    var isChecked: Bool

    init(id: String = ULID.generate(), text: String = "", isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}

/// A note is either free-form text or a checklist, never both — mirrors
/// how Google Keep notes work.
enum QuickNoteKind: String, Codable {
    case text
    case checklist
}

/// Google Keep-style color-coding for a note's card/editor background.
enum NoteColor: String, CaseIterable, Codable, Identifiable {
    case `default`
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink
    case brown
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .red: return "Coral"
        case .orange: return "Peach"
        case .yellow: return "Sand"
        case .green: return "Mint"
        case .teal: return "Teal"
        case .blue: return "Sky"
        case .indigo: return "Dusk"
        case .purple: return "Plum"
        case .pink: return "Blossom"
        case .brown: return "Clay"
        case .dark: return "Charcoal"
        }
    }

    /// Light pastel tint used as the note card/editor background.
    var background: Color {
        switch self {
        case .default: return Color(red: 1.0, green: 1.0, blue: 1.0)
        case .red: return Color(red: 0.98, green: 0.85, blue: 0.85)
        case .orange: return Color(red: 0.99, green: 0.89, blue: 0.82)
        case .yellow: return Color(red: 0.99, green: 0.96, blue: 0.82)
        case .green: return Color(red: 0.88, green: 0.96, blue: 0.88)
        case .teal: return Color(red: 0.86, green: 0.96, blue: 0.95)
        case .blue: return Color(red: 0.88, green: 0.93, blue: 0.98)
        case .indigo: return Color(red: 0.89, green: 0.89, blue: 0.97)
        case .purple: return Color(red: 0.94, green: 0.88, blue: 0.96)
        case .pink: return Color(red: 0.97, green: 0.87, blue: 0.92)
        case .brown: return Color(red: 0.92, green: 0.89, blue: 0.87)
        case .dark: return Color(red: 0.88, green: 0.89, blue: 0.91)
        }
    }

    /// Saturated swatch shown in the color picker itself.
    var swatch: Color {
        switch self {
        case .default: return Color(red: 0.95, green: 0.95, blue: 0.95)
        case .red: return Color(red: 0.72, green: 0.11, blue: 0.11)
        case .orange: return Color(red: 0.75, green: 0.28, blue: 0.08)
        case .yellow: return Color(red: 0.70, green: 0.45, blue: 0.02)
        case .green: return Color(red: 0.11, green: 0.42, blue: 0.22)
        case .teal: return Color(red: 0.00, green: 0.40, blue: 0.38)
        case .blue: return Color(red: 0.12, green: 0.42, blue: 0.53)
        case .indigo: return Color(red: 0.18, green: 0.24, blue: 0.45)
        case .purple: return Color(red: 0.34, green: 0.20, blue: 0.42)
        case .pink: return Color(red: 0.55, green: 0.18, blue: 0.30)
        case .brown: return Color(red: 0.35, green: 0.32, blue: 0.22)
        case .dark: return Color(red: 0.12, green: 0.13, blue: 0.15)
        }
    }
}

/// Google Keep-style visual background themes & vector SVG illustrations.
enum NoteTheme: String, CaseIterable, Codable, Identifiable {
    case none
    case places
    case food
    case music
    case grocery
    case notes
    case recipe
    case travel
    case video
    case celebration

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No Theme"
        case .places: return "Places"
        case .food: return "Food"
        case .music: return "Music"
        case .grocery: return "Groceries"
        case .notes: return "Notes"
        case .recipe: return "Recipe"
        case .travel: return "Travel"
        case .video: return "Video"
        case .celebration: return "Celebration"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .none:
            return []
        case .places:
            return [Color(red: 0.98, green: 0.90, blue: 0.82), Color(red: 0.95, green: 0.85, blue: 0.78)]
        case .food:
            return [Color(red: 0.90, green: 0.94, blue: 0.97), Color(red: 0.85, green: 0.90, blue: 0.95)]
        case .music:
            return [Color(red: 0.90, green: 0.92, blue: 0.92), Color(red: 0.85, green: 0.88, blue: 0.90)]
        case .grocery:
            return [Color(red: 0.92, green: 0.95, blue: 0.90), Color(red: 0.88, green: 0.92, blue: 0.86)]
        case .notes:
            return [Color(red: 0.92, green: 0.91, blue: 0.97), Color(red: 0.88, green: 0.87, blue: 0.95)]
        case .recipe:
            return [Color(red: 0.96, green: 0.90, blue: 0.92), Color(red: 0.92, green: 0.85, blue: 0.88)]
        case .travel:
            return [Color(red: 0.88, green: 0.94, blue: 0.98), Color(red: 0.84, green: 0.90, blue: 0.96)]
        case .video:
            return [Color(red: 0.91, green: 0.91, blue: 0.94), Color(red: 0.86, green: 0.86, blue: 0.90)]
        case .celebration:
            return [Color(red: 0.91, green: 0.90, blue: 0.96), Color(red: 0.87, green: 0.85, blue: 0.94)]
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "autumn": self = .places
        case "sketch": self = .notes
        case "forest": self = .recipe
        case "cinema": self = .video
        default:
            self = NoteTheme(rawValue: raw) ?? .none
        }
    }
}

/// A manually-written note — plain text, a checklist, JSON, code, links,
/// anything typed or pasted as text. There's no attachment affordance
/// anywhere in the UI, so media never enters this model.
struct QuickNote: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var title: String
    var text: String
    var checklistItems: [ChecklistItem]
    var kind: QuickNoteKind
    var color: NoteColor
    var theme: NoteTheme
    var customThemeId: String?
    var isPinned: Bool
    var isArchived: Bool
    /// Manual board position (ascending). Synced separately from content edits
    /// via `positionUpdatedAt` so reordering doesn't bump the "Updated" date.
    var sortOrder: Double
    var positionUpdatedAt: Date
    let createdAt: Date
    var updatedAt: Date
    /// Tombstone: kept and synced so the Drive merge can't resurrect a deleted note.
    var deletedAt: Date?

    init(
        id: String = ULID.generate(),
        title: String = "",
        text: String = "",
        checklistItems: [ChecklistItem] = [],
        kind: QuickNoteKind = .text,
        color: NoteColor = .default,
        theme: NoteTheme = .none,
        customThemeId: String? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false,
        sortOrder: Double = 0,
        positionUpdatedAt: Date = .distantPast,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.checklistItems = checklistItems
        self.kind = kind
        self.color = color
        self.theme = theme
        self.customThemeId = customThemeId
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.positionUpdatedAt = positionUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, text, checklistItems, kind, color, theme, customThemeId, isPinned, isArchived, sortOrder, positionUpdatedAt, createdAt, updatedAt, deletedAt
    }

    // Custom decoding for backward compatibility with notes saved before
    // title/checklist/color/theme/customThemeId/pin/archive existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        checklistItems = try container.decodeIfPresent([ChecklistItem].self, forKey: .checklistItems) ?? []
        kind = try container.decodeIfPresent(QuickNoteKind.self, forKey: .kind) ?? .text
        color = try container.decodeIfPresent(NoteColor.self, forKey: .color) ?? .default
        theme = try container.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .none
        customThemeId = try container.decodeIfPresent(String.self, forKey: .customThemeId)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Pre-reordering notes keep their newest-first order on every device.
        sortOrder = try container.decodeIfPresent(Double.self, forKey: .sortOrder) ?? -updatedAt.timeIntervalSince1970
        positionUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .positionUpdatedAt) ?? .distantPast
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encode(checklistItems, forKey: .checklistItems)
        try container.encode(kind, forKey: .kind)
        try container.encode(color, forKey: .color)
        try container.encode(theme, forKey: .theme)
        try container.encode(customThemeId, forKey: .customThemeId)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(positionUpdatedAt, forKey: .positionUpdatedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

extension QuickNote {
    /// Reuses the same text-kind detection clipboard items use, so a plain
    /// text note gets the familiar Text/Link/Code/Color badge in the UI.
    /// Only meaningful for `.text` notes; checklists have their own icon.
    var textContentKind: ClipboardContentKind {
        ClipboardContentKind.detect(from: text)
    }

    var detectedColor: DetectedColor? {
        kind == .text ? ColorDetector.detect(from: text) : nil
    }

    /// The first URL found anywhere in the note's text — not just when the
    /// whole note is a bare link, so "check this: https://…" still surfaces
    /// an Open in Browser action.
    var detectedLink: URL? {
        guard kind == .text, !text.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, range: range) else { return nil }
        return match.url
    }

    var checkedItemCount: Int {
        checklistItems.filter { $0.isChecked }.count
    }

    var isSensitive: Bool {
        guard AppSettings.shared.maskSensitiveContent else { return false }
        if SensitiveContentDetector.looksSensitive(title) || SensitiveContentDetector.looksSensitive(text) {
            return true
        }
        if kind == .checklist {
            return checklistItems.contains { SensitiveContentDetector.looksSensitive($0.text) }
        }
        return false
    }

    /// Renders the note's plain-text body as `AttributedString`, interpreting
    /// lightweight inline markdown (`**bold**`, `_italic_`, `~~strikethrough~~`)
    /// typed from the formatting toolbar. The stored text itself stays plain
    /// so sync/search/backward-compatibility are all unaffected; this is a
    /// read-only rendering used in cards and the editor's live preview.
    var renderedText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Turns note markdown into a compact card preview: block markers become
/// glyphs (☐ ☑ • ❝) and inline styles render, so cards never show raw syntax.
enum MarkdownPreview {
    static func render(_ markdown: String) -> AttributedString {
        let lines = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        let formatted = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                return "☐ " + String(trimmed.dropFirst(6))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                return "☑ ~~\(String(trimmed.dropFirst(6)))~~"
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return "• " + String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("> ") {
                return "❝ " + String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("### ") {
                return "**" + String(trimmed.dropFirst(4)) + "**"
            } else if trimmed.hasPrefix("## ") {
                return "**" + String(trimmed.dropFirst(3)) + "**"
            } else if trimmed.hasPrefix("# ") {
                return "**" + String(trimmed.dropFirst(2)) + "**"
            }
            return line
        }
        let joined = formatted.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: joined, options: options)) ?? AttributedString(joined)
    }
}
