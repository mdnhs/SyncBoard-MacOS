//
//  ClipboardItem.swift
//  SyncBoard
//

import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let text: String
    let date: Date
    let isSensitive: Bool
    var isPinned: Bool

    init(
        id: String = ULID.generate(),
        text: String,
        date: Date = Date(),
        isSensitive: Bool? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.isSensitive = isSensitive ?? SensitiveContentDetector.looksSensitive(text)
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, date, isSensitive, isPinned
    }

    // Custom decoding for backward compatibility with UUID and string formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringID = try? container.decode(String.self, forKey: .id) {
            self.id = stringID
        } else if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid.uuidString
        } else {
            self.id = ULID.generate()
        }

        self.text = try container.decode(String.self, forKey: .text)
        self.date = try container.decode(Date.self, forKey: .date)
        self.isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive)
            ?? SensitiveContentDetector.looksSensitive(text)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(date, forKey: .date)
        try container.encode(isSensitive, forKey: .isSensitive)
        try container.encode(isPinned, forKey: .isPinned)
    }
}
