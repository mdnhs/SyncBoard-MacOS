//
//  CodeBlockView.swift
//  SyncBoard
//

import SwiftUI

/// Renders a code segment as an editor-style window: a copy button, a
/// detected language badge, and line-numbered, syntax-highlighted source.
struct CodeBlockView: View {
    let code: String
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var didCopy = false

    private var lines: [String] {
        code.components(separatedBy: "\n")
    }

    private var language: CodeLanguage {
        CodeLanguage.detect(from: code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            codeBody
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var header: some View {
        HStack {
            trafficLights
            Spacer()
            Text(language.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
            copyButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // Purely decorative — a macOS window chrome look to make the snippet
    // read as a code editor at a glance.
    private var trafficLights: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(red: 1.0, green: 0.373, blue: 0.341)).frame(width: 9, height: 9) // #FF5F57
            Circle().fill(Color(red: 0.996, green: 0.737, blue: 0.180)).frame(width: 9, height: 9) // #FEBC2E
            Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.251)).frame(width: 9, height: 9) // #28C840
        }
    }

    // Copies just this code segment, not the item's full text (which may
    // also include surrounding prose) — a distinct action from the detail
    // page's main "Copy to Clipboard" button.
    private var copyButton: some View {
        Button {
            clipboardManager.copyRawText(code)
            withAnimation(.snappy) { didCopy = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.snappy) { didCopy = false }
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(didCopy ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy code snippet")
    }

    private var codeBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(width: 16, alignment: .trailing)
                    CodeSyntaxHighlighter.highlight(line, language: language)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding(10)
        .textSelection(.enabled)
    }
}

/// A lightweight, per-language-aware highlighter — good enough for common
/// snippets people copy; not a general-purpose lexer.
enum CodeSyntaxHighlighter {
    private static var patternCache: [CodeLanguage: NSRegularExpression] = [:]

    static func highlight(_ line: String, language: CodeLanguage) -> Text {
        guard let regex = regex(for: language) else { return Text(line) }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        var segments: [Text] = []
        var lastIndex = 0

        for match in regex.matches(in: line, range: fullRange) {
            if match.range.location > lastIndex {
                let gap = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                segments.append(Text(nsLine.substring(with: gap)).foregroundColor(.secondary))
            }
            let matched = nsLine.substring(with: match.range)
            segments.append(Text(matched).foregroundColor(color(for: match)))
            lastIndex = match.range.location + match.range.length
        }

        if lastIndex < nsLine.length {
            let tail = NSRange(location: lastIndex, length: nsLine.length - lastIndex)
            segments.append(Text(nsLine.substring(with: tail)).foregroundColor(.secondary))
        }

        return segments.reduce(Text(""), +)
    }

    private static func regex(for language: CodeLanguage) -> NSRegularExpression? {
        if let cached = patternCache[language] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern(for: language)) else { return nil }
        patternCache[language] = regex
        return regex
    }

    private static func pattern(for language: CodeLanguage) -> String {
        if language == .json {
            return #"(?<key>"(?:\\.|[^"\\])*"(?=\s*:))|(?<string>"(?:\\.|[^"\\])*")|(?<literal>\btrue\b|\bfalse\b|\bnull\b)|(?<number>-?\d+(?:\.\d+)?\b)"#
        }

        let commentPattern = (language == .python || language == .shell) ? "#.*$" : "//.*$"
        var parts = [
            "(?<comment>\(commentPattern))",
            #"(?<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')"#
        ]
        if !language.keywords.isEmpty {
            let alternation = language.keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            parts.append("(?<keyword>\\b(?:\(alternation))\\b)")
        }
        parts.append(#"(?<number>\b\d+(?:\.\d+)?\b)"#)
        return parts.joined(separator: "|")
    }

    private static func color(for match: NSTextCheckingResult) -> Color {
        func has(_ name: String) -> Bool {
            match.range(withName: name).location != NSNotFound
        }
        if has("key") { return .purple }
        if has("string") { return .green }
        if has("literal") { return .blue }
        if has("keyword") { return .pink }
        if has("comment") { return .secondary }
        if has("number") { return .orange }
        return .primary
    }
}

#Preview {
    CodeBlockView(code: """
    {
      "data":
        {
          "public_id": "01hz...",
          "star_rating": 4,
          "postal_code": "1212",
          "email_verified_at": null
        }
    }
    """)
    .padding()
    .frame(width: 360)
    .environment(ClipboardManager.shared)
}
