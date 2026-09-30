//
//  MenuBarPopoverView.swift
//  SyncBoard
//

import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(\.dismissPopover) private var dismissPopover
    @State private var searchText = ""
    @State private var selectedTab: ClipboardContentKind?
    @FocusState private var isSearchFocused: Bool

    private var filteredHistory: [ClipboardItem] {
        var items = clipboardManager.history
        if let selectedTab {
            items = items.filter { $0.contentKind == selectedTab }
        }
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private var groupedHistory: [(section: String, items: [ClipboardItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredHistory) { item -> String in
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
        NavigationStack {
            VStack(spacing: 0) {
                header
                searchField
                filterTabs
                if filteredHistory.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color.primaryBackground)
            .navigationDestination(for: ClipboardItem.self) { item in
                ClipboardItemDetailView(item: item)
            }
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("SyncBoard")
                    .font(.headline)
                Text("\(clipboardManager.history.count) item\(clipboardManager.history.count == 1 ? "" : "s") in history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            commandKBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }

    private var commandKBadge: some View {
        HStack(spacing: 1) {
            Image(systemName: "command")
            Text("K")
        }
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }

    private var filterTabs: some View {
        HStack(spacing: 2) {
            filterTabButton(title: "All", isSelected: selectedTab == nil) {
                selectedTab = nil
            }
            ForEach(ClipboardContentKind.allCases) { kind in
                filterTabButton(title: kind.rawValue, isSelected: selectedTab == kind) {
                    selectedTab = kind
                }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func filterTabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No clipboard history yet" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedHistory, id: \.section) { group in
                    Section {
                        ForEach(group.items) { item in
                            let isLastInList = item.id == filteredHistory.last?.id
                            PopoverRow(
                                item: item,
                                isLastInList: isLastInList && filteredHistory.count > 1
                            ) {
                                clipboardManager.copyToPasteboard(item)
                                dismissPopover()
                            }
                        }
                    } header: {
                        sectionHeader(group)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 22)
            .scrollControlSize(.mini)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }

    private func sectionHeader(_ group: (section: String, items: [ClipboardItem])) -> some View {
        HStack {
            Text(group.section.uppercased())
            Spacer()
            Text("\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .background(Color.primaryBackground)
    }

    private var footer: some View {
        HStack {
            Button("Clear All") {
                clipboardManager.clearAll()
            }
            .buttonStyle(.plain)
            .foregroundStyle(clipboardManager.history.isEmpty ? Color.secondary : Color.red)
            .disabled(clipboardManager.history.isEmpty)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct PopoverRow: View {
    let item: ClipboardItem
    let isLastInList: Bool
    let onCopy: () -> Void
    @State private var isHovering = false
    @State private var isButtonHovering = false

    // The chevron button must be a sibling of the copy target rather than nested
    // inside it; a NavigationLink placed within the card's tap area never
    // receives the click, because the card's gesture consumes it first.
    var body: some View {
        ZStack(alignment: .bottom) {
            if isLastInList {
                stackedDeckBackground
            }

            ZStack(alignment: .topTrailing) {
                card
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .onTapGesture(perform: onCopy)
                    .onHover { isHovering = $0 }

                NavigationLink(value: item) {
                    chevronButton
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 12)
            }
            .overlay(alignment: .topTrailing) {
                if isButtonHovering {
                    floatingTooltip("Click to view details")
                        .offset(x: 0, y: -26)
                        .zIndex(999)
                } else if isHovering {
                    floatingTooltip("Click to copy")
                        .offset(x: -36, y: -26)
                        .zIndex(999)
                }
            }
        }
        .padding(.bottom, isLastInList ? 14 : 0)
        .zIndex(isHovering || isButtonHovering ? 100 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isButtonHovering)
    }

    private var stackedDeckBackground: some View {
        ZStack(alignment: .bottom) {
            // Layer 2 (Bottom-most peek layer)
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.04), radius: 3, y: 2)
                .padding(.horizontal, 20)
                .frame(height: 48)
                .offset(y: 12)

            // Layer 1 (Middle peek layer)
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                .padding(.horizontal, 10)
                .frame(height: 48)
                .offset(y: 6)
        }
    }

    private func floatingTooltip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.85))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .fixedSize()
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private var chevronButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isButtonHovering ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isButtonHovering ? .primary : .secondary)
        }
        .frame(width: 26, height: 26)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isButtonHovering = $0 }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.contentKind.color)
                    .frame(width: 40, height: 40)
                Image(systemName: item.contentKind.iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Copied from Mac")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // Reserves the space the overlaid chevron button occupies.
                    Color.clear
                        .frame(width: 26, height: 16)
                }

                // Collapsed to one flowing line rather than truncated at the
                // first embedded newline, so multi-line content (like a code
                // snippet with a comment above it) still reads as one preview.
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .font(item.contentKind == .code ? .callout.monospaced() : .callout)
                    .foregroundStyle(item.contentKind == .code ? item.contentKind.color : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Text("\(item.text.count) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    Text(item.contentKind.displayLabel)
                        .font(.caption)
                        .foregroundStyle(item.contentKind.color)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0), radius: 8, y: 2)
    }
}

#Preview {
    MenuBarPopoverView()
        .environment(ClipboardManager.shared)
}
