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
    private var driveSync: GoogleDriveSyncManager { .shared }

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
                if let error = driveSync.lastError {
                    driveSyncErrorBanner(error)
                }
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

            HStack(spacing: 8) {
                googleDriveButton

                Button {
                    AppSettings.openSettingsWindow()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 30, height: 30)
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Open Settings (⌘,)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var googleDriveButton: some View {
        Menu {
            if driveSync.isConnected {
                if let email = driveSync.accountEmail {
                    Text(email)
                }
                Button("Sync Now") { driveSync.syncNow() }
                Button("Disconnect", role: .destructive) { driveSync.disconnect() }
            } else {
                Button("Connect Google Drive") {
                    Task { await driveSync.connect() }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(driveSync.isConnected ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                    .frame(width: 30, height: 30)
                if driveSync.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: driveSync.isConnected ? "checkmark.icloud.fill" : "icloud")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(driveSync.isConnected ? Color.green : Color.secondary)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(driveSync.isConnected ? "Synced with Google Drive (\(driveSync.accountEmail ?? ""))" : "Connect Google Drive")
    }

    private func driveSyncErrorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                driveSync.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
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
        let items: [ClipboardContentKind?] = [nil] + ClipboardContentKind.allCases.map { Optional($0) }
        return AppPillTabs(
            selection: $selectedTab,
            items: items,
            title: { $0?.rawValue ?? "All" }
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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
            LazyVStack(spacing: 12) {
                ForEach(groupedHistory, id: \.section) { group in
                    Section {
                        ForEach(group.items) { item in
                            PopoverRow(
                                item: item,
                                onCopy: {
                                    clipboardManager.copyToPasteboard(item)
                                    dismissPopover()
                                },
                                onTogglePin: {
                                    clipboardManager.togglePin(for: item)
                                },
                                onDelete: {
                                    clipboardManager.delete(item)
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: -12)),
                                removal: .opacity
                            ))
                        }
                    } header: {
                        sectionHeader(group)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 24)
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
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false
    @State private var isButtonHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            card
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture(perform: onCopy)
                .onHover { isHovering = $0 }
                .contextMenu {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    Button(action: onTogglePin) {
                        Label(item.isPinned ? "Unpin Item" : "Pin Item", systemImage: item.isPinned ? "pin.slash" : "pin.fill")
                    }

                    if let colorInfo = item.detectedColor {
                        Menu("Copy Color Format") {
                            Button("HEX (\(colorInfo.hexString))") { ClipboardManager.shared.copyRawText(colorInfo.hexString) }
                            Button("RGB (\(colorInfo.rgbString))") { ClipboardManager.shared.copyRawText(colorInfo.rgbString) }
                            Button("HSL (\(colorInfo.hslString))") { ClipboardManager.shared.copyRawText(colorInfo.hslString) }
                            Button("SwiftUI Color") { ClipboardManager.shared.copyRawText(colorInfo.swiftUIString) }
                            Button("NSColor") { ClipboardManager.shared.copyRawText(colorInfo.nsColorCodeString) }
                        }
                    }

                    Menu("Transform & Copy") {
                        ForEach(TextTransformer.Action.allCases) { action in
                            Button {
                                if let res = TextTransformer.transform(item.text, using: action) {
                                    ClipboardManager.shared.copyRawText(res)
                                }
                            } label: {
                                Label(action.rawValue, systemImage: action.iconName)
                            }
                        }
                    }

                    Divider()

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }

            NavigationLink(value: item) {
                detailButton
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
        .zIndex(isHovering || isButtonHovering ? 100 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isButtonHovering)
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

    private var detailButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isButtonHovering ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isButtonHovering ? .primary : .secondary)
        }
        .frame(width: 26, height: 26)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isButtonHovering = $0 }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            if let colorInfo = item.detectedColor {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorInfo.color)
                        .frame(width: 40, height: 40)
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 40, height: 40)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(item.contentKind.color)
                        .frame(width: 40, height: 40)
                    Image(systemName: item.contentKind.iconName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if item.isPinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.orange)
                            .fixedSize()
                    } else if let colorInfo = item.detectedColor {
                        Text(colorInfo.hexString)
                            .font(.caption.monospaced())
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.pink)
                    } else {
                        Text("Copied from Mac")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // Reserves the space the overlaid chevron button occupies.
                    Color.clear
                        .frame(width: 26, height: 16)
                }

                SensitiveTextReveal(
                    text: item.text.replacingOccurrences(of: "\n", with: " "),
                    isSensitive: item.isSensitive
                ) { displayText in
                    Text(displayText)
                        .font(item.contentKind == .code ? .callout.monospaced() : .callout)
                        .foregroundStyle(item.contentKind == .code ? item.contentKind.color : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

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

                    Spacer(minLength: 0)

                    DeviceOriginLabel(origin: item.origin)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(item.isPinned ? Color.orange.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0), radius: 8, y: 2)
    }
}

#Preview {
    MenuBarPopoverView()
        .environment(ClipboardManager.shared)
}
