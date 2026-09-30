//
//  ContentView.swift
//  SyncBoard
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var selectedCategory: SidebarCategory? = .all
    @State private var selectedItem: ClipboardItem?
    @State private var searchText = ""
    @State private var showClearConfirmation = false
    @State private var copiedConfirmation = false

    private enum SidebarCategory: Hashable, Identifiable {
        case all
        case kind(ClipboardContentKind)

        var id: String {
            switch self {
            case .all: return "all"
            case .kind(let kind): return kind.id
            }
        }

        var title: String {
            switch self {
            case .all: return "All Items"
            case .kind(let kind):
                switch kind {
                case .code: return "Code Snippets"
                case .link: return "Links & URLs"
                case .text: return "Text Snippets"
                }
            }
        }

        var iconName: String {
            switch self {
            case .all: return "doc.on.clipboard"
            case .kind(let kind): return kind.iconName
            }
        }

        var color: Color {
            switch self {
            case .all: return .accentColor
            case .kind(let kind): return kind.color
            }
        }
    }

    private var filteredItems: [ClipboardItem] {
        var items = clipboardManager.history

        if let selectedCategory {
            switch selectedCategory {
            case .all:
                break
            case .kind(let kind):
                items = items.filter { $0.contentKind == kind }
            }
        }

        guard !searchText.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private var groupedItems: [(section: String, items: [ClipboardItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredItems) { item -> String in
            if calendar.isDateInToday(item.date) {
                return "Today"
            } else if calendar.isDateInYesterday(item.date) {
                return "Yesterday"
            } else {
                return item.date.formatted(date: .abbreviated, time: .omitted)
            }
        }
        let priority = ["Today": 0, "Yesterday": 1]
        return groups.keys.sorted { lhs, rhs in
            switch (priority[lhs], priority[rhs]) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (groups[lhs]?.first?.date ?? .distantPast) > (groups[rhs]?.first?.date ?? .distantPast)
            }
        }.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            contentList
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 480)
        } detail: {
            detailInspector
                .navigationSplitViewColumnWidth(min: 400, ideal: 520)
        }
        .frame(minWidth: 960, minHeight: 560)
        .confirmationDialog(
            "Clear all clipboard history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                clipboardManager.clearAll()
                selectedItem = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all items from your clipboard history.")
        }
    }

    // MARK: - Column 1: Sidebar
    private var sidebar: some View {
        List(selection: $selectedCategory) {
            Section("Library") {
                NavigationLink(value: SidebarCategory.all) {
                    sidebarRow(category: .all, count: clipboardManager.history.count)
                }
            }

            Section("Categories") {
                ForEach(ClipboardContentKind.allCases) { kind in
                    let category = SidebarCategory.kind(kind)
                    let count = clipboardManager.history.filter { $0.contentKind == kind }.count
                    NavigationLink(value: category) {
                        sidebarRow(category: category, count: count)
                    }
                }
            }

            Section("Shortcuts & Tips") {
                VStack(alignment: .leading, spacing: 8) {
                    shortcutTipRow(label: "Quick Popover", shortcut: "⌘ ⇧ V")
                    shortcutTipRow(label: "Search Bar", shortcut: "⌘ K")
                    shortcutTipRow(label: "Copy Item", shortcut: "⌘ C")
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SyncBoard")
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    private func sidebarRow(category: SidebarCategory, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.iconName)
                .foregroundStyle(category.color)
                .frame(width: 18)
            Text(category.title)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private func shortcutTipRow(label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(shortcut)
                .font(.caption2.monospaced())
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(clipboardManager.history.isEmpty ? Color.secondary : Color.red)
                .disabled(clipboardManager.history.isEmpty)

                Spacer()

                Text("\(clipboardManager.history.count) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Column 2: Content List
    private var contentList: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()

            if filteredItems.isEmpty {
                emptyListState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedItems, id: \.section) { group in
                            Section {
                                ForEach(group.items) { item in
                                    AppClipboardCard(
                                        item: item,
                                        isSelected: selectedItem?.id == item.id,
                                        onSelect: { selectedItem = item },
                                        onCopy: {
                                            clipboardManager.copyToPasteboard(item)
                                            withAnimation(.snappy) { copiedConfirmation = true }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                                withAnimation(.snappy) { copiedConfirmation = false }
                                            }
                                        },
                                        onDelete: {
                                            if selectedItem?.id == item.id {
                                                selectedItem = nil
                                            }
                                            clipboardManager.delete(item)
                                        }
                                    )
                                }
                            } header: {
                                listSectionHeader(group)
                            }
                        }
                    }
                    .padding(12)
                    .scrollControlSize(.mini)
                }
                .background(Color.primaryBackground)
            }
        }
        .navigationTitle(selectedCategory?.title ?? "Items")
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search in \(selectedCategory?.title ?? "history")...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        .padding(10)
        .background(.bar)
    }

    private func listSectionHeader(_ group: (section: String, items: [ClipboardItem])) -> some View {
        HStack {
            Text(group.section.uppercased())
            Spacer()
            Text("\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(Color.primaryBackground)
    }

    private var emptyListState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No items in this category" : "No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Button("Clear Search") { searchText = "" }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryBackground)
    }

    // MARK: - Column 3: Detail Inspector
    private var detailInspector: some View {
        Group {
            if let item = selectedItem {
                AppDetailInspectorView(
                    item: item,
                    onCopy: {
                        clipboardManager.copyToPasteboard(item)
                    },
                    onDelete: {
                        selectedItem = nil
                        clipboardManager.delete(item)
                    }
                )
            } else {
                emptyDetailState
            }
        }
        .background(Color.primaryBackground)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("Select an Item")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Choose an item from the list to view its complete content, syntax, and details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - App Clipboard Card Component
private struct AppClipboardCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(item.contentKind.color)
                    .frame(width: 36, height: 36)
                Image(systemName: item.contentKind.iconName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.contentKind.displayLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(item.contentKind.color)

                    Spacer(minLength: 8)

                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .font(item.contentKind == .code ? .callout.monospaced() : .callout)
                    .foregroundStyle(item.contentKind == .code ? item.contentKind.color : Color.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text("\(item.text.count) chars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())

                    Spacer()

                    if isHovering || isSelected {
                        HStack(spacing: 4) {
                            Button(action: onCopy) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                                    .padding(5)
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Copy to clipboard")

                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .padding(5)
                                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Delete item")
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .shadow(color: .black.opacity(isHovering ? 0.05 : 0), radius: 4, y: 1)
    }
}

// MARK: - App Detail Inspector View Component
private struct AppDetailInspectorView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var didCopy = false

    private var wordCount: Int {
        item.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private var lineCount: Int {
        item.text.components(separatedBy: "\n").count
    }

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if item.contentKind == .link, let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        linkActionBanner(url: url)
                    }

                    ForEach(item.textSegments) { segment in
                        if segment.isCode {
                            CodeBlockView(code: segment.text)
                        } else {
                            Text(segment.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                        }
                    }
                }
                .padding(16)
                .scrollControlSize(.mini)
            }

            Divider()
            inspectorFooter
        }
    }

    private var inspectorHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.contentKind.color)
                    .frame(width: 30, height: 30)
                Image(systemName: item.contentKind.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.contentKind.displayLabel)
                    .font(.headline)
                Text("Copied \(item.date.formatted(date: .complete, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onCopy()
                withAnimation(.snappy) { didCopy = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.snappy) { didCopy = false }
                }
            } label: {
                Label(didCopy ? "Copied!" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: .command)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help("Delete item")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func linkActionBanner(url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Web Link Detected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Open in Browser") {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.green.opacity(0.2)))
    }

    private var inspectorFooter: some View {
        HStack(spacing: 16) {
            metaBadge(title: "Characters", value: "\(item.text.count)")
            metaBadge(title: "Words", value: "\(wordCount)")
            metaBadge(title: "Lines", value: "\(lineCount)")
            Spacer()
            Text("ID: \(item.id.uuidString.prefix(8))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func metaBadge(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title + ":")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

#Preview {
    ContentView()
        .environment(ClipboardManager.shared)
}
