//
//  CodeLanguage.swift
//  SyncBoard
//

import Foundation

/// A heuristic language guess from code structure/syntax — not a real
/// parser, just pattern matching good enough to label and lightly
/// highlight the kinds of snippets people actually copy.
enum CodeLanguage: String, CaseIterable {
    case json = "JSON"
    case swift = "Swift"
    case python = "Python"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case html = "HTML"
    case css = "CSS"
    case shell = "Shell"
    case sql = "SQL"
    case generic = "Code"

    var keywords: [String] {
        switch self {
        case .swift:
            return ["func", "var", "let", "struct", "class", "enum", "protocol", "extension", "import",
                     "guard", "if", "else", "for", "while", "return", "private", "public", "static", "self", "true", "false", "nil"]
        case .python:
            return ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while",
                     "self", "None", "True", "False", "with", "try", "except"]
        case .javascript, .typescript:
            return ["function", "const", "let", "var", "return", "if", "else", "for", "while", "import",
                     "export", "from", "class", "new", "this", "true", "false", "null", "async", "await"]
        case .shell:
            return ["echo", "if", "then", "fi", "for", "do", "done", "export", "cd"]
        case .sql:
            return ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "JOIN", "ON", "GROUP", "BY", "ORDER"]
        case .json, .html, .css, .generic:
            return []
        }
    }

    static func detect(from code: String) -> CodeLanguage {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return .json
        }
        if trimmed.hasPrefix("<") && (trimmed.contains("</") || trimmed.contains("/>")) {
            return .html
        }
        if trimmed.range(of: #"\b(SELECT|INSERT|UPDATE|DELETE)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .sql
        }
        if trimmed.hasPrefix("#!") || trimmed.range(of: #"\b(echo|fi|done)\b"#, options: .regularExpression) != nil {
            return .shell
        }
        if trimmed.range(of: #"\bfunc\s+\w+\s*\("#, options: .regularExpression) != nil
            || trimmed.contains("@State") || trimmed.contains("SwiftUI")
            || trimmed.range(of: #"\b(var|let)\s+\w+\s*:\s*\w+"#, options: .regularExpression) != nil {
            return .swift
        }
        if trimmed.range(of: #"\bdef\s+\w+\s*\("#, options: .regularExpression) != nil
            || (trimmed.contains("self.") && !trimmed.contains(";")) {
            return .python
        }
        if trimmed.range(of: #"\b(function|const|let|var)\s+\w+"#, options: .regularExpression) != nil
            || trimmed.contains("=>") || trimmed.contains("console.log") {
            return trimmed.range(of: #":\s*(string|number|boolean)\b"#, options: .regularExpression) != nil ? .typescript : .javascript
        }
        if trimmed.range(of: #"^[.#]?[\w-]+\s*\{"#, options: .regularExpression) != nil
            && trimmed.contains(":") && trimmed.contains(";") {
            return .css
        }

        return .generic
    }
}
