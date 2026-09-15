//
//  ClipboardContentKind.swift
//  SyncBoard
//

import SwiftUI

enum ClipboardContentKind: String, CaseIterable, Identifiable {
    case text = "Text"
    case link = "Links"
    case code = "Code"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .text: return "Text snippet"
        case .link: return "Link preview"
        case .code: return "Code snippet"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "doc.plaintext.fill"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var color: Color {
        switch self {
        case .text: return .blue
        case .link: return .green
        case .code: return .orange
        }
    }

    static func detect(from text: String) -> ClipboardContentKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.range(of: #"^(https?://|www\.)\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .link
        }

        let codeMarkers = ["{", "}", ";", "func ", "class ", "import ", "const ", "let ", "def ", "return ", "=>"]
        let matchCount = codeMarkers.reduce(into: 0) { count, marker in
            if trimmed.contains(marker) { count += 1 }
        }
        if matchCount >= 2 {
            return .code
        }

        return .text
    }
}

extension ClipboardItem {
    var contentKind: ClipboardContentKind {
        ClipboardContentKind.detect(from: text)
    }

    /// Splits mixed content (e.g. an explanation followed by a JSON block)
    /// into runs of plain-prose lines and runs of code-like lines, so only
    /// the actual code gets a code-block treatment when displayed.
    var textSegments: [ClipboardTextSegment] {
        let lines = text.components(separatedBy: "\n")
        var result: [ClipboardTextSegment] = []
        var currentLines: [String] = []
        var currentIsCode: Bool?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A blank line carries no signal on its own (code and prose both
            // have blank lines); keep it attached to whatever segment it's
            // already inside instead of forcing a prose classification.
            let isCode = trimmed.isEmpty ? (currentIsCode ?? false) : Self.lineLooksLikeCode(line)
            if currentIsCode == nil || currentIsCode == isCode {
                currentLines.append(line)
                currentIsCode = isCode
            } else {
                result.append(ClipboardTextSegment(text: currentLines.joined(separator: "\n"), isCode: currentIsCode == true))
                currentLines = [line]
                currentIsCode = isCode
            }
        }
        if !currentLines.isEmpty {
            result.append(ClipboardTextSegment(text: currentLines.joined(separator: "\n"), isCode: currentIsCode == true))
        }
        return result
    }

    private static func lineLooksLikeCode(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        // Comment lines (// # /* *) are part of the surrounding code, not
        // prose — without this, a commented line splits the snippet in two.
        if ["//", "#", "/*", "*", "--"].contains(where: trimmed.hasPrefix) { return true }
        if ["{", "}", "[", "]"].contains(where: trimmed.hasPrefix) { return true }
        if [";", "{", "(", ","].contains(where: trimmed.hasSuffix) { return true }
        if trimmed.range(of: #"^"[^"]+"\s*:"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^(func|class|import|const|let|var|def|return)\b"#, options: .regularExpression) != nil { return true }
        return false
    }
}

struct ClipboardTextSegment: Identifiable {
    let id = UUID()
    let text: String
    let isCode: Bool
}
