//
//  ULID.swift
//  SyncBoard
//

import Foundation

/// Universally Unique Lexicographically Sortable Identifier (ULID)
/// 128-bit identifier: 48-bit timestamp (milliseconds) + 80-bit cryptographic entropy.
/// Encoded in Crockford's Base32 (26 characters).
public struct ULID: Identifiable, Hashable, Equatable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public var id: String { rawValue }
    public var description: String { rawValue }

    private static let encodingChars: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let charMap: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (index, char) in encodingChars.enumerated() {
            map[char] = UInt8(index)
            map[Character(char.lowercased())] = UInt8(index)
        }
        // Crockford aliases
        map["O"] = 0; map["o"] = 0
        map["I"] = 1; map["i"] = 1; map["L"] = 1; map["l"] = 1
        return map
    }()

    public init(timestamp: Date = Date()) {
        let ms = UInt64(timestamp.timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)

        // 48-bit timestamp (big-endian)
        bytes[0] = UInt8((ms >> 40) & 0xFF)
        bytes[1] = UInt8((ms >> 32) & 0xFF)
        bytes[2] = UInt8((ms >> 24) & 0xFF)
        bytes[3] = UInt8((ms >> 16) & 0xFF)
        bytes[4] = UInt8((ms >> 8) & 0xFF)
        bytes[5] = UInt8(ms & 0xFF)

        // 80-bit random entropy
        _ = SecRandomCopyBytes(kSecRandomDefault, 10, &bytes[6])

        self.rawValue = Self.encode(bytes: bytes)
    }

    public init?(string: String) {
        guard string.count == 26 else { return nil }
        let upper = string.uppercased()
        guard upper.allSatisfy({ Self.charMap[$0] != nil }) else { return nil }
        self.rawValue = upper
    }

    public static func generate(timestamp: Date = Date()) -> String {
        ULID(timestamp: timestamp).rawValue
    }

    public var timestamp: Date {
        let chars = Array(rawValue.prefix(10))
        var ms: UInt64 = 0
        for char in chars {
            guard let val = Self.charMap[char] else { continue }
            ms = (ms << 5) | UInt64(val)
        }
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    public static func < (lhs: ULID, rhs: ULID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        self.rawValue = str
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func encode(bytes: [UInt8]) -> String {
        var result = ""
        result.reserveCapacity(26)

        // 10 chars for 48-bit timestamp (6 bytes)
        var t0 = UInt64(bytes[0]) << 40 | UInt64(bytes[1]) << 32 | UInt64(bytes[2]) << 24 |
                 UInt64(bytes[3]) << 16 | UInt64(bytes[4]) << 8  | UInt64(bytes[5])

        var timeChars = [Character](repeating: "0", count: 10)
        for i in (0..<10).reversed() {
            timeChars[i] = encodingChars[Int(t0 & 0x1F)]
            t0 >>= 5
        }
        result.append(contentsOf: timeChars)

        // 16 chars for 80-bit randomness (10 bytes)
        var r0 = UInt64(bytes[6]) << 32 | UInt64(bytes[7]) << 24 | UInt64(bytes[8]) << 16 | UInt64(bytes[9]) << 8 | UInt64(bytes[10])
        var r1 = UInt64(bytes[11]) << 32 | UInt64(bytes[12]) << 24 | UInt64(bytes[13]) << 16 | UInt64(bytes[14]) << 8 | UInt64(bytes[15])

        var randChars = [Character](repeating: "0", count: 16)
        for i in (8..<16).reversed() {
            randChars[i] = encodingChars[Int(r1 & 0x1F)]
            r1 >>= 5
        }
        for i in (0..<8).reversed() {
            randChars[i] = encodingChars[Int(r0 & 0x1F)]
            r0 >>= 5
        }
        result.append(contentsOf: randChars)

        return result
    }
}
