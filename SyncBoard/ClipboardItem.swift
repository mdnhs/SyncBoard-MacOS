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
    /// Copied from a password manager (`org.nspasteboard.ConcealedType`), so it
    /// stays masked whatever the text-based detector says.
    let isConcealed: Bool
    var isPinned: Bool
    /// `nil` for items captured before origins were recorded.
    let origin: DeviceOrigin?

    init(
        id: String = ULID.generate(),
        text: String,
        date: Date = Date(),
        isSensitive: Bool? = nil,
        isConcealed: Bool = false,
        isPinned: Bool = false,
        origin: DeviceOrigin? = .current
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.isSensitive = isConcealed || (isSensitive ?? SensitiveContentDetector.looksSensitive(text))
        self.isConcealed = isConcealed
        self.isPinned = isPinned
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, date, isSensitive, isConcealed, isPinned, origin
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
        let storedSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive)
        if let isConcealed = try container.decodeIfPresent(Bool.self, forKey: .isConcealed) {
            self.isConcealed = isConcealed
            self.isSensitive = isConcealed || (storedSensitive ?? SensitiveContentDetector.looksSensitive(text))
        } else {
            // Saved before the detector fix: re-check old flags, which had many false
            // positives. This can only unmask, never newly mask, an item.
            self.isConcealed = false
            self.isSensitive = (storedSensitive ?? true) && SensitiveContentDetector.looksSensitive(text)
        }
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.origin = try container.decodeIfPresent(DeviceOrigin.self, forKey: .origin)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(date, forKey: .date)
        try container.encode(isSensitive, forKey: .isSensitive)
        try container.encode(isConcealed, forKey: .isConcealed)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(origin, forKey: .origin)
    }
}
