//
//  ClipboardItemDetailView.swift
//  SyncBoard
//

import SwiftUI

struct ClipboardItemDetailView: View {
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissPopover) private var dismissPopover
    let item: ClipboardItem

    // The copy button lives inside the same ScrollView as the content
    // (rather than as a fixed sibling below it) so it sits directly under
    // short content instead of a ScrollView greedily filling the popover's
    // full height and stranding the button at the very bottom.\
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if item.contentKind == .code {
                            Text(item.contentKind.displayLabel)
                                .font(.caption.monospaced())
                                .foregroundStyle(item.contentKind.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.contentKind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(item.textSegments) { segment in
                            if segment.isCode {
                                CodeBlockView(code: segment.text)
                            } else {
                                Text(segment.text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    Button {
                        // Copying is the end of this flow for a menu-bar
                        // quick-access panel, so close it immediately rather
                        // than leaving it open.
                        clipboardManager.copyToPasteboard(item)
                        dismissPopover()
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("c", modifiers: .command)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .scrollControlSize(.mini)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primaryBackground)
    }

    // The popover has no window title bar, so NavigationStack's automatic
    // back chevron never renders; this bar stands in for it explicitly.
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Back")

            Spacer()

            Text("Clipboard Item")
                .font(.headline)

            Spacer()

            Button(role: .destructive) {
                clipboardManager.delete(item)
                dismiss()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Delete item")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

#Preview {
    NavigationStack {
        ClipboardItemDetailView(item: ClipboardItem(text: "Sample clipboard text for preview purposes."))
    }
    .environment(ClipboardManager.shared)
}
