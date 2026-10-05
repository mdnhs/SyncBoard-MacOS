//
//  NoteDiff.swift
//  SyncBoard
//

import Foundation

/// The diffable parts of a note. Checklists flatten to `☐`/`☑` lines so a
/// ticked box reads as an edit like any other text change.
struct NoteSnapshot: Equatable {
    let title: String
    let kind: QuickNoteKind
    let body: String

    init(title: String, text: String, checklistItems: [ChecklistItem], kind: QuickNoteKind) {
        self.title = title
        self.kind = kind
        if kind == .checklist {
            body = checklistItems.map { "\($0.isChecked ? "☑" : "☐") \($0.text)" }.joined(separator: "\n")
        } else {
            body = text
        }
    }

    init(_ revision: NoteRevision) {
        self.init(title: revision.title, text: revision.text, checklistItems: revision.checklistItems, kind: revision.kind)
    }

    init(_ note: QuickNote) {
        self.init(title: note.title, text: note.text, checklistItems: note.checklistItems, kind: note.kind)
    }
}

struct InlineDiffSegment: Equatable {
    enum Kind { case unchanged, added, removed }

    let kind: Kind
    let text: String
}

/// Line- and word-level diff between two versions of a note, rendered inline the way
/// Google Docs version history marks insertions and deletions.
struct NoteInlineDiff {
    let title: [InlineDiffSegment]
    let body: [InlineDiffSegment]
    let kindChange: (old: QuickNoteKind, new: QuickNoteKind)?
    let addedWords: Int
    let removedWords: Int

    var titleChanged: Bool { title.contains { $0.kind != .unchanged } }

    /// `old == nil` (the first known version) shows the content without markup.
    init(from old: NoteSnapshot?, to new: NoteSnapshot) {
        guard let old else {
            title = [InlineDiffSegment(kind: .unchanged, text: new.title)]
            body = [InlineDiffSegment(kind: .unchanged, text: new.body)]
            kindChange = nil
            addedWords = 0
            removedWords = 0
            return
        }
        title = Self.segments(from: old.title, to: new.title)
        body = Self.segments(from: old.body, to: new.body)
        kindChange = old.kind == new.kind ? nil : (old.kind, new.kind)
        addedWords = Self.wordCount(in: title + body, kind: .added)
        removedWords = Self.wordCount(in: title + body, kind: .removed)
    }

    /// Compares line by line first so a new or deleted line is marked whole,
    /// then word by word inside lines that were edited in place.
    static func segments(from old: String, to new: String) -> [InlineDiffSegment] {
        let oldLines = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let newLines = new.isEmpty ? [] : new.components(separatedBy: "\n")
        let lineOps = align(oldLines, newLines)

        var segments: [InlineDiffSegment] = []
        func append(_ kind: InlineDiffSegment.Kind, _ text: String) {
            guard !text.isEmpty else { return }
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1] = InlineDiffSegment(kind: kind, text: last.text + text)
            } else {
                segments.append(InlineDiffSegment(kind: kind, text: text))
            }
        }

        // Line breaks follow their line's kind, so hiding deletions never leaves a stray blank line.
        var hasNewLine = false
        func emit(_ kind: InlineDiffSegment.Kind, line: [InlineDiffSegment]) {
            if kind == .removed {
                let text = line.map(\.text).joined()
                if hasNewLine { append(.removed, "\n" + text) } else { append(.removed, text + "\n") }
            } else {
                if hasNewLine { append(kind == .added ? .added : .unchanged, "\n") }
                line.forEach { append($0.kind, $0.text) }
                hasNewLine = true
            }
        }

        var index = 0
        while index < lineOps.count {
            if lineOps[index].kind == .unchanged {
                emit(.unchanged, line: [InlineDiffSegment(kind: .unchanged, text: lineOps[index].text)])
                index += 1
                continue
            }
            var removedLines: [String] = []
            var addedLines: [String] = []
            while index < lineOps.count, lineOps[index].kind != .unchanged {
                if lineOps[index].kind == .removed { removedLines.append(lineOps[index].text) } else { addedLines.append(lineOps[index].text) }
                index += 1
            }
            for pair in pairLines(removed: removedLines, added: addedLines) {
                switch pair {
                case let (oldLine?, newLine?):
                    emit(.unchanged, line: align(tokenize(oldLine), tokenize(newLine)))
                case let (oldLine?, nil):
                    emit(.removed, line: [InlineDiffSegment(kind: .removed, text: oldLine)])
                case let (nil, newLine?):
                    emit(.added, line: [InlineDiffSegment(kind: .added, text: newLine)])
                case (nil, nil):
                    break
                }
            }
        }
        return segments
    }

    /// Walks Swift's Myers diff to interleave deletions, insertions, and
    /// unchanged elements in document order, deletions first.
    private static func align(_ old: [String], _ new: [String]) -> [InlineDiffSegment] {
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var result: [InlineDiffSegment] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count, removed.contains(oldIndex) {
                result.append(InlineDiffSegment(kind: .removed, text: old[oldIndex]))
                oldIndex += 1
            } else if newIndex < new.count, inserted.contains(newIndex) {
                result.append(InlineDiffSegment(kind: .added, text: new[newIndex]))
                newIndex += 1
            } else {
                result.append(InlineDiffSegment(kind: .unchanged, text: new[newIndex]))
                oldIndex += 1
                newIndex += 1
            }
        }
        return result
    }

    /// Treats a deleted and an added line as one edited line only when they
    /// share enough words; otherwise they stay a separate deletion and insertion.
    /// Order is preserved, so the output still reads top to bottom.
    private static func pairLines(removed: [String], added: [String]) -> [(String?, String?)] {
        if removed.count == 1, added.count == 1 {
            return [(removed[0], added[0])]
        }
        var result: [(String?, String?)] = []
        // Unmatched insertions wait until the deletions before them are emitted, like Docs.
        var pendingAdded: [String] = []
        var nextRemoved = 0
        for newLine in added {
            let candidates = removed.indices.dropFirst(nextRemoved)
            let best = candidates.max { similarity(removed[$0], newLine) < similarity(removed[$1], newLine) }
            if let best, similarity(removed[best], newLine) >= 0.4 {
                removed[nextRemoved..<best].forEach { result.append(($0, nil)) }
                pendingAdded.forEach { result.append((nil, $0)) }
                pendingAdded = []
                result.append((removed[best], newLine))
                nextRemoved = best + 1
            } else {
                pendingAdded.append(newLine)
            }
        }
        removed[nextRemoved...].forEach { result.append(($0, nil)) }
        pendingAdded.forEach { result.append((nil, $0)) }
        return result
    }

    /// Dice coefficient over the lines' words.
    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsWords = words(in: lhs)
        let rhsWords = words(in: rhs)
        guard !lhsWords.isEmpty || !rhsWords.isEmpty else { return 1 }
        var remaining = Dictionary(rhsWords.map { ($0, 1) }, uniquingKeysWith: +)
        var shared = 0
        for word in lhsWords where remaining[word, default: 0] > 0 {
            remaining[word, default: 0] -= 1
            shared += 1
        }
        return Double(2 * shared) / Double(lhsWords.count + rhsWords.count)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Splits into runs of letters/digits and runs of whitespace; every other
    /// character is its own token, so "plan" → "plan:" reads as an added colon.
    private static func tokenize(_ text: String) -> [String] {
        enum Class { case word, space, symbol }
        func classify(_ character: Character) -> Class {
            if character.isWhitespace { return .space }
            if character.isLetter || character.isNumber { return .word }
            return .symbol
        }

        var tokens: [String] = []
        var current = ""
        var currentClass: Class = .space
        for character in text {
            let characterClass = classify(character)
            if !current.isEmpty, characterClass != currentClass || characterClass == .symbol {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            currentClass = characterClass
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func wordCount(in segments: [InlineDiffSegment], kind: InlineDiffSegment.Kind) -> Int {
        segments
            .filter { $0.kind == kind }
            .reduce(0) { $0 + words(in: $1.text).count }
    }
}
