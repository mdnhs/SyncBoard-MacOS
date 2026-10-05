//
//  NoteHistoryView.swift
//  SyncBoard
//

import SwiftUI

/// Google Docs-style version history: the selected version rendered as a
/// document with its edits marked inline, and a version list on the right.
struct NoteHistoryView: View {
    let note: QuickNote
    let onRestore: (NoteRevision) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var loadState: LoadState = .loading
    @State private var selectedID: String?
    @State private var showsChanges = true
    @State private var isRevealed = false
    @State private var pendingRestore: NoteRevision?

    private enum LoadState {
        case loading
        case loaded([HistoryEntry])
        case failed(String)
    }

    private var driveSync: GoogleDriveSyncManager { .shared }

    private var selectedEntry: HistoryEntry? {
        guard case .loaded(let entries) = loadState else { return nil }
        return entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            content
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 560, idealHeight: 660)
        .task(id: note.id) { await load() }
        .onChange(of: selectedID) { isRevealed = false }
        .confirmationDialog(
            "Restore this version?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { revision in
            Button("Restore") { onRestore(revision) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your note will go back to this version. The current version stays in the history once it has synced.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to note")

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedEntry.map { $0.date.formatted(date: .long, time: .shortened) } ?? "Version history")
                    .font(.headline)
                Text(note.title.isEmpty ? "Untitled note" : note.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let entry = selectedEntry {
                if entry.isSensitive {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Label(isRevealed ? "Hide" : "Reveal", systemImage: isRevealed ? "eye.slash" : "eye")
                    }
                }
                if let revision = entry.revision, !entry.isCurrent {
                    Button("Restore this version") { pendingRestore = revision }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !driveSync.isConnected {
            placeholder(icon: "icloud.slash", message: "Connect Google Drive in Settings to keep a version history for your notes.")
        } else {
            switch loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 10) {
                    placeholder(icon: "exclamationmark.triangle", message: message)
                    Button("Try Again") { Task { await load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let entries) where entries.isEmpty:
                placeholder(icon: "clock", message: "No versions yet. Edits are saved as versions when they sync to Google Drive.")
            case .loaded(let entries):
                HStack(spacing: 0) {
                    if let entry = selectedEntry {
                        document(entry)
                    }
                    Divider()
                    sidebar(entries)
                        .frame(width: 290)
                }
            }
        }
    }

    // MARK: - Document

    private func document(_ entry: HistoryEntry) -> some View {
        let isMasked = entry.isSensitive && !isRevealed
        let highlights = showsChanges && !isMasked
        let color = AuthorColor.color(for: entry.origin)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if highlights, let kindChange = entry.diff.kindChange {
                    Label(
                        kindChange.new == .checklist ? "Turned into a check list in this version" : "Turned into a text note in this version",
                        systemImage: "arrow.left.arrow.right"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if isMasked {
                    Label("This version contains sensitive content. Reveal it to see the changes.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let title = rendered(entry.diff.title, color: color, highlights: highlights, isMasked: isMasked)
                Text(title.characters.isEmpty ? AttributedString("Untitled") : title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(title.characters.isEmpty ? Color.secondary : Color.primary)

                let body = rendered(entry.diff.body, color: color, highlights: highlights, isMasked: isMasked)
                Text(body.characters.isEmpty ? AttributedString("Empty note") : body)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(body.characters.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(maxWidth: 700, minHeight: 480, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 3, y: 1)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.35) : Color.primary.opacity(0.05))
    }

    /// Added text takes the author's color with a tint; deleted text is struck
    /// through in the same color, like Google Docs.
    private func rendered(_ segments: [InlineDiffSegment], color: Color, highlights: Bool, isMasked: Bool) -> AttributedString {
        if isMasked {
            let plain = segments.filter { $0.kind != .removed }.map(\.text).joined()
            return AttributedString(SensitiveContentDetector.mask(plain))
        }
        var result = AttributedString()
        for segment in segments {
            if segment.kind == .removed && !highlights { continue }
            var piece = AttributedString(segment.text)
            if highlights {
                switch segment.kind {
                case .added:
                    piece.foregroundColor = color
                    piece.backgroundColor = color.opacity(0.16)
                case .removed:
                    piece.foregroundColor = color.opacity(0.8)
                    piece.strikethroughStyle = .single
                    piece.backgroundColor = color.opacity(0.08)
                case .unchanged:
                    break
                }
            }
            result += piece
        }
        return result
    }

    // MARK: - Sidebar

    private func sidebar(_ entries: [HistoryEntry]) -> some View {
        VStack(spacing: 0) {
            Text("Version history")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(HistoryEntry.sections(entries), id: \.title) { section in
                        Text(section.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        ForEach(section.entries) { entry in
                            versionRow(entry, showsDate: section.showsDate)
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show changes", isOn: $showsChanges)
                    .toggleStyle(.checkbox)
                if showsChanges {
                    HStack(spacing: 12) {
                        Text("Added")
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 3)
                            .background(Color.accentColor.opacity(0.16))
                        Text("Deleted")
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color.primary.opacity(0.02))
    }

    private func versionRow(_ entry: HistoryEntry, showsDate: Bool) -> some View {
        let isSelected = entry.id == selectedEntry?.id

        return Button {
            selectedID = entry.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(showsDate
                     ? entry.date.formatted(date: .abbreviated, time: .shortened)
                     : entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)

                if entry.isCurrent {
                    Text(entry.revision == nil ? "Current version · not synced yet" : "Current version")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }

                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(AuthorColor.color(for: entry.origin))
                        .frame(width: 8, height: 8)
                    Text(entry.origin?.name ?? "Unknown device")
                        .font(.caption)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placeholder(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func load() async {
        guard driveSync.isConnected else { return }
        if case .failed = loadState { loadState = .loading }
        do {
            let revisions = try await driveSync.noteHistory(for: note.id)
            let entries = HistoryEntry.build(revisions: revisions, current: note)
            loadState = .loaded(entries)
            if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
                selectedID = entries.first?.id
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

/// A stable color per device, used for its dot and its highlighted edits.
private enum AuthorColor {
    private static let palette: [Color] = [.blue, .purple, .orange, .pink, .teal, .green, .indigo, .brown]

    static func color(for origin: DeviceOrigin?) -> Color {
        guard let origin else { return .gray }
        // `hashValue` is reseeded every launch, so derive the index from the ID itself.
        let sum = origin.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// One version in the list: a synced revision, or the note's current content
/// when it hasn't synced yet.
private struct HistoryEntry: Identifiable {
    let id: String
    /// `nil` for unsynced current content, which can't be restored.
    let revision: NoteRevision?
    let diff: NoteInlineDiff
    let date: Date
    let origin: DeviceOrigin?
    let summary: String
    let isCurrent: Bool
    let isSensitive: Bool

    struct Section {
        let title: String
        let showsDate: Bool
        let entries: [HistoryEntry]
    }

    static func sections(_ entries: [HistoryEntry]) -> [Section] {
        let calendar = Calendar.current
        var sections: [Section] = []
        for entry in entries {
            let title: String
            let showsDate: Bool
            if calendar.isDateInToday(entry.date) {
                (title, showsDate) = ("Today", false)
            } else if calendar.isDateInYesterday(entry.date) {
                (title, showsDate) = ("Yesterday", false)
            } else {
                (title, showsDate) = (entry.date.formatted(.dateTime.month(.wide).year()), true)
            }
            if let last = sections.last, last.title == title {
                sections[sections.count - 1] = Section(title: title, showsDate: showsDate, entries: last.entries + [entry])
            } else {
                sections.append(Section(title: title, showsDate: showsDate, entries: [entry]))
            }
        }
        return sections
    }

    /// `revisions` must be newest first; each is compared with the next older one.
    static func build(revisions: [NoteRevision], current note: QuickNote) -> [HistoryEntry] {
        let current = NoteSnapshot(note)
        let snapshots = revisions.map { NoteSnapshot($0) }
        // Only a limited number of revisions is kept, so the oldest may not be the note's creation.
        let isComplete = revisions.count < GoogleDriveNoteHistoryService.maxRevisionsPerNote

        var entries: [HistoryEntry] = []
        if snapshots.first != current {
            let diff = NoteInlineDiff(from: snapshots.first, to: current)
            entries.append(HistoryEntry(
                id: "current",
                revision: nil,
                diff: diff,
                date: note.updatedAt,
                origin: .current,
                summary: snapshots.isEmpty ? "Created" : summary(for: diff),
                isCurrent: true,
                isSensitive: isSensitive(current)
            ))
        }

        for (index, revision) in revisions.enumerated() {
            let parent = snapshots.indices.contains(index + 1) ? snapshots[index + 1] : nil
            let diff = NoteInlineDiff(from: parent, to: snapshots[index])
            entries.append(HistoryEntry(
                id: revision.id,
                revision: revision,
                diff: diff,
                date: revision.savedAt,
                origin: revision.origin,
                summary: parent == nil ? (isComplete ? "Created" : "Oldest saved version") : summary(for: diff),
                isCurrent: index == 0 && snapshots[index] == current,
                isSensitive: isSensitive(snapshots[index])
            ))
        }
        return entries
    }

    private static func summary(for diff: NoteInlineDiff) -> String {
        if let kindChange = diff.kindChange {
            return kindChange.new == .checklist ? "Turned into a check list" : "Turned into a text note"
        }
        switch (diff.addedWords, diff.removedWords) {
        case (0, 0):
            return diff.titleChanged ? "Changed the title" : "Changed spacing"
        case (let added, 0):
            return "Added \(words(added))"
        case (0, let removed):
            return "Deleted \(words(removed))"
        case (let added, let removed):
            return "Edited · added \(words(added)), deleted \(words(removed))"
        }
    }

    private static func words(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count) words"
    }

    private static func isSensitive(_ snapshot: NoteSnapshot) -> Bool {
        AppSettings.shared.maskSensitiveContent
            && (SensitiveContentDetector.looksSensitive(snapshot.title) || SensitiveContentDetector.looksSensitive(snapshot.body))
    }
}
