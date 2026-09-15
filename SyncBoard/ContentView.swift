//
//  ContentView.swift
//  SyncBoard
//

import SwiftUI

struct ContentView: View {
    @Environment(ClipboardManager.self) private var clipboardManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if clipboardManager.history.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private var header: some View {
        HStack {
            Text("Clipboard History")
                .font(.headline)
            Spacer()
            Button("Clear All", role: .destructive) {
                clipboardManager.clearAll()
            }
            .disabled(clipboardManager.history.isEmpty)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No clipboard history yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(clipboardManager.history) { item in
                ClipboardRow(item: item)
            }
        }
        .listStyle(.inset)
    }
}

private struct ClipboardRow: View {
    @Environment(ClipboardManager.self) private var clipboardManager
    let item: ClipboardItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .lineLimit(2)
                Text(item.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                clipboardManager.delete(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            clipboardManager.copyToPasteboard(item)
        }
    }
}

#Preview {
    ContentView()
        .environment(ClipboardManager.shared)
}
