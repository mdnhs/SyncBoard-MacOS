//
//  TextTransformer.swift
//  SyncBoard
//

import Foundation

enum TextTransformer {
    enum Action: String, CaseIterable, Identifiable {
        case plainText = "Plain Text"
        case upperCase = "UPPERCASE"
        case lowerCase = "lowercase"
        case titleCase = "Title Case"
        case camelCase = "camelCase"
        case snakeCase = "snake_case"
        case kebabCase = "kebab-case"
        case jsonFormat = "Format JSON"
        case jsonMinify = "Minify JSON"
        case urlEncode = "URL Encode"
        case urlDecode = "URL Decode"
        case base64Encode = "Base64 Encode"
        case base64Decode = "Base64 Decode"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .plainText: return "doc.plaintext"
            case .upperCase: return "textformat.size.larger"
            case .lowerCase: return "textformat.size.smaller"
            case .titleCase: return "textformat"
            case .camelCase: return "character"
            case .snakeCase: return "minus"
            case .kebabCase: return "minus.rectangle"
            case .jsonFormat: return "curlybraces"
            case .jsonMinify: return "arrow.right.and.line.vertical.and.arrow.left"
            case .urlEncode: return "link.badge.plus"
            case .urlDecode: return "link"
            case .base64Encode: return "lock"
            case .base64Decode: return "lock.open"
            }
        }
    }

    static func transform(_ text: String, using action: Action) -> String? {
        switch action {
        case .plainText:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .upperCase:
            return text.uppercased()
        case .lowerCase:
            return text.lowercased()
        case .titleCase:
            return text.capitalized
        case .camelCase:
            return toCamelCase(text)
        case .snakeCase:
            return toSnakeCase(text)
        case .kebabCase:
            return toKebabCase(text)
        case .jsonFormat:
            return formatJSON(text)
        case .jsonMinify:
            return minifyJSON(text)
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        case .urlDecode:
            return text.removingPercentEncoding
        case .base64Encode:
            return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let decoded = String(data: data, encoding: .utf8) else {
                return nil
            }
            return decoded
        }
    }

    private static func words(from text: String) -> [String] {
        let pattern = #"[A-Z]?[a-z]+|[A-Z]+(?=[A-Z][a-z]|\d|\b)|[0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let extracted = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
        return extracted.isEmpty ? text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty } : extracted
    }

    private static func toCamelCase(_ text: String) -> String {
        let wordList = words(from: text)
        guard let first = wordList.first?.lowercased() else { return text }
        let rest = wordList.dropFirst().map { $0.capitalized }
        return ([first] + rest).joined()
    }

    private static func toSnakeCase(_ text: String) -> String {
        let wordList = words(from: text)
        return wordList.map { $0.lowercased() }.joined(separator: "_")
    }

    private static func toKebabCase(_ text: String) -> String {
        let wordList = words(from: text)
        return wordList.map { $0.lowercased() }.joined(separator: "-")
    }

    private static func formatJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let formattedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let formattedString = String(data: formattedData, encoding: .utf8) else {
            return nil
        }
        return formattedString
    }

    private static func minifyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let minifiedData = try? JSONSerialization.data(withJSONObject: json, options: []),
              let minifiedString = String(data: minifiedData, encoding: .utf8) else {
            return nil
        }
        return minifiedString
    }
}
