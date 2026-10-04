//
//  ClipboardContentKind.swift
//  SyncBoard
//

import SwiftUI

enum ClipboardContentKind: String, CaseIterable, Identifiable {
    case text = "Text"
    case link = "Links"
    case code = "Code"
    case color = "Colors"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .text: return "Text snippet"
        case .link: return "Link preview"
        case .code: return "Code snippet"
        case .color: return "Color preview"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "doc.plaintext.fill"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette.fill"
        }
    }

    var color: Color {
        switch self {
        case .text: return .blue
        case .link: return .green
        case .code: return .orange
        case .color: return .pink
        }
    }

    static func detect(from text: String) -> ClipboardContentKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if ColorDetector.detect(from: trimmed) != nil {
            return .color
        }

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

    var detectedColor: DetectedColor? {
        ColorDetector.detect(from: text)
    }

    /// Splits mixed content into runs of plain-prose lines and runs of code-like lines.
    var textSegments: [ClipboardTextSegment] {
        let lines = text.components(separatedBy: "\n")
        var result: [ClipboardTextSegment] = []
        var currentLines: [String] = []
        var currentIsCode: Bool?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
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
