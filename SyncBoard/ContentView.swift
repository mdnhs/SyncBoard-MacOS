//
//  ContentView.swift
//  SyncBoard
//

import SwiftUI
import AppKit

/// What's shown in the sidebar: either a clipboard-history filter, the To Do
/// Kanban board, or the Quick Notes grid.
enum SidebarSelection: Hashable {
    case filter(ContentFilter)
    case quickNotes
    case todo
}

/// Filter tabs for Quick Notes (mirrors the popover tab design)
enum QuickNoteFilterTab: String, CaseIterable, Identifiable {
    case all = "All"
    case text = "Text"
    case checklist = "Checklist"
    case archived = "Archived"

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var selection: SidebarSelection = .filter(.all)
    @State private var selectedItem: ClipboardItem?
    @State private var selectedTodo: TodoItem?
    @State private var selectedNote: QuickNote?
    @State private var selectedNoteTab: QuickNoteFilterTab = .all
    @State private var searchText = ""
    @State private var copiedConfirmation = false
    @State private var quickNotesGridWidth: CGFloat = 800
    @FocusState private var isSearchFocused: Bool
    private var driveSync: GoogleDriveSyncManager { .shared }
    private var todoManager: TodoManager { .shared }
    private var quickNoteManager: QuickNoteManager { .shared }

    private var showArchivedNotes: Bool {
        selectedNoteTab == .archived
    }

    private var currentFilter: ContentFilter {
        if case .filter(let filter) = selection { return filter }
        return .all
    }

    /// Both the To Do board and the Quick Notes grid use the full-width
    /// content column + drawer-overlay editor pattern, instead of the
    /// narrower content/detail split the clipboard views use.
    private var isShowingWideBoard: Bool {
        selection == .todo || selection == .quickNotes
    }

    private var filteredItems: [ClipboardItem] {
        clipboardManager.history.filter { item in
            let matchesFilter: Bool
            switch currentFilter {
            case .all:
                matchesFilter = true
            case .pinned:
                matchesFilter = item.isPinned
            case .text:
                matchesFilter = item.contentKind == .text
            case .code:
                matchesFilter = item.contentKind == .code
            case .link:
                matchesFilter = item.contentKind == .link
            case .color:
                matchesFilter = item.detectedColor != nil
            case .sensitive:
                matchesFilter = item.isSensitive
            }

            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            return item.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedItems: [(section: String, items: [ClipboardItem])] {
        let items = filteredItems
        if items.isEmpty { return [] }

        var result: [(section: String, items: [ClipboardItem])] = []
        let pinned = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }

        if !pinned.isEmpty && currentFilter != .pinned {
            result.append((section: "Pinned Items", items: pinned))
        }

        let normalList = (currentFilter == .pinned) ? pinned : unpinned
        let calendar = Calendar.current
        let today = normalList.filter { calendar.isDateInToday($0.date) }
        let yesterday = normalList.filter { calendar.isDateInYesterday($0.date) }
        let earlier = normalList.filter { !calendar.isDateInToday($0.date) && !calendar.isDateInYesterday($0.date) }

        if !today.isEmpty {
            result.append((section: "Today", items: today))
        }
        if !yesterday.isEmpty {
            result.append((section: "Yesterday", items: yesterday))
        }
        if !earlier.isEmpty {
            result.append((section: "Earlier", items: earlier))
        }

        return result
    }

    private var filteredTodoItems: [TodoItem] {
        let items = todoManager.items
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.notes.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredNotes: [QuickNote] {
        let base: [QuickNote]
        switch selectedNoteTab {
        case .all:
            base = quickNoteManager.notes.filter { !$0.isArchived }
        case .text:
            base = quickNoteManager.notes.filter { !$0.isArchived && $0.kind == .text }
        case .checklist:
            base = quickNoteManager.notes.filter { !$0.isArchived && $0.kind == .checklist }
        case .archived:
            base = quickNoteManager.notes.filter { $0.isArchived }
        }

        guard !searchText.isEmpty else { return base }
        return base.filter { note in
            note.title.localizedCaseInsensitiveContains(searchText)
                || note.text.localizedCaseInsensitiveContains(searchText)
                || note.checklistItems.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var pinnedNotes: [QuickNote] {
        showArchivedNotes ? [] : filteredNotes.filter { $0.isPinned }
    }

    private var unpinnedNotes: [QuickNote] {
        showArchivedNotes ? filteredNotes : filteredNotes.filter { !$0.isPinned }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } content: {
            Group {
                switch selection {
                case .filter:
                    contentList
                case .quickNotes:
                    quickNotesGrid
                case .todo:
                    todoBoard
                }
            }
            .navigationSplitViewColumnWidth(
                min: isShowingWideBoard ? 600 : 320,
                ideal: isShowingWideBoard ? 2000 : 360,
                max: isShowingWideBoard ? 2000 : 480
            )
        } detail: {
            Group {
                switch selection {
                case .filter:
                    detailInspector
                case .quickNotes, .todo:
                    // Neither the Quick Notes nor the To Do editor is shown
                    // as a permanent column — both slide in as a drawer
                    // overlay (see below), and this column is collapsed to
                    // ~0 width so the board gets the full window until
                    // something is actually selected.
                    Color.clear
                }
            }
            .navigationSplitViewColumnWidth(
                min: isShowingWideBoard ? 1 : 400,
                ideal: isShowingWideBoard ? 1 : 460,
                max: isShowingWideBoard ? 1 : 520
            )
        }
        .frame(minWidth: 960, minHeight: 560)
        .background(TitlebarSeparatorHider())
        .background {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .hidden()
        }
        .overlay {
            if selection == .todo, let task = selectedTodo {
                todoDrawer(task)
            } else if selection == .quickNotes, let note = selectedNote {
                quickNoteDrawer(note)
            }
        }
    }

    // MARK: - To Do: Drawer Overlay
    private func todoDrawer(_ task: TodoItem) -> some View {
        let liveTask = todoManager.items.first(where: { $0.id == task.id }) ?? task

        return ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissTodoDrawer() }

            TodoEditorView(
                item: liveTask,
                onUpdate: { title, notes in
                    todoManager.updateContent(liveTask, title: title, notes: notes)
                },
                onStatusChange: { status in
                    todoManager.moveStatus(liveTask, to: status)
                },
                onSetColor: { color in
                    todoManager.setColor(liveTask, color: color)
                },
                onSetTheme: { theme in
                    todoManager.setTheme(liveTask, theme: theme)
                },
                onSetCustomTheme: { customThemeId in
                    todoManager.setCustomTheme(liveTask, customThemeId: customThemeId)
                },
                onClose: { dismissTodoDrawer() },
                onDelete: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTodo = nil
                        todoManager.delete(liveTask)
                    }
                }
            )
            .frame(width: 420)
            .clipped()
            .transition(.move(edge: .trailing))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedTodo)
    }

    private func dismissTodoDrawer() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            selectedTodo = nil
        }
    }

    // MARK: - Quick Notes: Drawer Overlay
    private func quickNoteDrawer(_ note: QuickNote) -> some View {
        let liveNote = quickNoteManager.notes.first(where: { $0.id == note.id }) ?? note

        return ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissQuickNoteDrawer() }

            QuickNoteEditorView(
                note: liveNote,
                onUpdateText: { title, text in
                    quickNoteManager.updateContent(liveNote, title: title, text: text)
                },
                onUpdateChecklist: { title, items in
                    quickNoteManager.updateChecklist(liveNote, title: title, items: items)
                },
                onTogglePin: { quickNoteManager.togglePin(liveNote) },
                onSetColor: { color in quickNoteManager.setColor(liveNote, color: color) },
                onSetTheme: { theme in quickNoteManager.setTheme(liveNote, theme: theme) },
                onSetCustomTheme: { customThemeId in quickNoteManager.setCustomTheme(liveNote, customThemeId: customThemeId) },
                onToggleArchive: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedNote = nil
                        quickNoteManager.setArchived(liveNote, isArchived: !liveNote.isArchived)
                    }
                },
                onClose: { dismissQuickNoteDrawer() },
                onDelete: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedNote = nil
                        quickNoteManager.delete(liveNote)
                    }
                }
            )
            .frame(width: 420)
            .clipped()
            .transition(.move(edge: .trailing))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedNote)
    }

    private func dismissQuickNoteDrawer() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            selectedNote = nil
        }
    }

    // MARK: - Column 1: Sidebar
    private var sidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                NavigationLink(value: SidebarSelection.filter(.all)) {
                    sidebarRow(filter: .all, count: clipboardManager.history.count)
                }
                NavigationLink(value: SidebarSelection.filter(.pinned)) {
                    sidebarRow(filter: .pinned, count: clipboardManager.history.filter { $0.isPinned }.count)
                }
                NavigationLink(value: SidebarSelection.quickNotes) {
                    quickNotesSidebarRow
                }
                NavigationLink(value: SidebarSelection.todo) {
                    todoSidebarRow
                }
            }

            Section("Categories") {
                NavigationLink(value: SidebarSelection.filter(.text)) {
                    sidebarRow(filter: .text, count: clipboardManager.history.filter { $0.contentKind == .text }.count)
                }
                NavigationLink(value: SidebarSelection.filter(.code)) {
                    sidebarRow(filter: .code, count: clipboardManager.history.filter { $0.contentKind == .code }.count)
                }
                NavigationLink(value: SidebarSelection.filter(.link)) {
                    sidebarRow(filter: .link, count: clipboardManager.history.filter { $0.contentKind == .link }.count)
                }
                NavigationLink(value: SidebarSelection.filter(.color)) {
                    sidebarRow(filter: .color, count: clipboardManager.history.filter { $0.detectedColor != nil }.count)
                }
            }

            Section("Security") {
                NavigationLink(value: SidebarSelection.filter(.sensitive)) {
                    sidebarRow(filter: .sensitive, count: clipboardManager.history.filter { $0.isSensitive }.count)
                }
            }

            Section("Preferences") {
                Button {
                    AppSettings.openSettingsWindow()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.primary)
                            .frame(width: 18)
                        Text("Settings")
                        Spacer()
                        Text("⌘,")
                            .font(.caption2.monospaced())
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .scrollControlSize(.mini)
        .navigationTitle("SyncBoard")
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    private func sidebarRow(filter: ContentFilter, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: filter.iconName)
                .foregroundStyle(Color.primary)
                .frame(width: 18)
            Text(filter.title)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private var quickNotesSidebarRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .foregroundStyle(Color.primary)
                .frame(width: 18)
            Text("Quick Notes")
            Spacer()
            Text("\(quickNoteManager.notes.filter { !$0.isArchived }.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private var todoSidebarRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .foregroundStyle(Color.primary)
                .frame(width: 18)
            Text("To Do")
            Spacer()
            Text("\(todoManager.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private var sidebarFooter: some View {
        googleDriveRow
            .background(.bar)
    }

    private var googleDriveRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(driveSync.isConnected ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                    .frame(width: 32, height: 32)
                Image(systemName: driveSync.isConnected ? "checkmark.icloud.fill" : "icloud")
                    .font(.callout)
                    .foregroundStyle(driveSync.isConnected ? Color.green : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Google Drive")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if driveSync.isConnected, let email = driveSync.accountEmail {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let error = driveSync.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if driveSync.isSyncing {
                ProgressView()
                    .controlSize(.small)
            } else if driveSync.isConnected {
                Menu {
                    Button("Sync Now") { driveSync.syncNow() }
                    Button("Disconnect", role: .destructive) { driveSync.disconnect() }
                } label: {
                    Color.primary.opacity(0.06)
                        .clipShape(Circle())
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Button("Connect") { Task { await driveSync.connect() } }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Column 2: Content List
    private var contentList: some View {
        VStack(spacing: 0) {
            searchHeader

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
                                        onTogglePin: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                clipboardManager.togglePin(for: item)
                                            }
                                        },
                                        onCopy: {
                                            clipboardManager.copyToPasteboard(item)
                                            withAnimation(.snappy) { copiedConfirmation = true }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                                withAnimation(.snappy) { copiedConfirmation = false }
                                            }
                                        },
                                        onDelete: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                if selectedItem?.id == item.id {
                                                    selectedItem = nil
                                                }
                                                clipboardManager.delete(item)
                                            }
                                        }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.94).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            } header: {
                                listSectionHeader(group)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .padding(12)
                    .scrollControlSize(.mini)
                }
                .background(Color.primaryBackground)
            }
        }
        .background(Color.primaryBackground)
        .navigationTitle(currentFilter.title)
    }

    private var searchHeader: some View {
        appSearchBar(placeholder: "Search in \(currentFilter.title)...")
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
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
                    onTogglePin: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            clipboardManager.togglePin(for: item)
                        }
                    },
                    onCopy: {
                        clipboardManager.copyToPasteboard(item)
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedItem = nil
                            clipboardManager.delete(item)
                        }
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
                Text("Choose an item from the list to view its complete content, syntax, and transformations.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - To Do: Column 2 (Kanban Board)
    private var todoBoard: some View {
        VStack(spacing: 0) {
            todoHeader

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(TodoStatus.allCases) { status in
                        todoColumn(status)
                    }
                }
                .padding(16)
                .scrollControlSize(.mini)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.primaryBackground)
        }
        .background(Color.primaryBackground)
        .navigationTitle("To Do")
    }

    private var todoHeader: some View {
        HStack(spacing: 10) {
            Button {
                let newTask = todoManager.createItem(title: "New Task")
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedTodo = newTask
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("New Task")

            appSearchBar(placeholder: "Search tasks...")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func todoColumn(_ status: TodoStatus) -> some View {
        let items = filteredTodoItems.filter { $0.status == status }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(status.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        TodoCard(
                            item: item,
                            isSelected: selectedTodo?.id == item.id,
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    selectedTodo = item
                                }
                            },
                            onSetColor: { color in
                                todoManager.setColor(item, color: color)
                            },
                            onSetTheme: { theme in
                                todoManager.setTheme(item, theme: theme)
                            },
                            onSetCustomTheme: { customThemeId in
                                todoManager.setCustomTheme(item, customThemeId: customThemeId)
                            },
                            onDelete: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    if selectedTodo?.id == item.id { selectedTodo = nil }
                                    todoManager.delete(item)
                                }
                            }
                        )
                        .draggable(item.id)
                    }

                    if items.isEmpty {
                        Text("No tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
                .scrollControlSize(.mini)
            }
        }
        .padding(10)
        .frame(width: 220, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let item = todoManager.items.first(where: { $0.id == id }) else { return false }
            todoManager.moveStatus(item, to: status)
            return true
        }
    }

}

// MARK: - To Do Card Component
private struct TodoCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: TodoItem
    let isSelected: Bool
    let onSelect: () -> Void
    var onSetColor: ((NoteColor) -> Void)? = nil
    var onSetTheme: ((NoteTheme) -> Void)? = nil
    var onSetCustomTheme: ((String?) -> Void)? = nil
    let onDelete: () -> Void
    @State private var isHovering = false
    @State private var showBackgroundPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SensitiveTextReveal(
                text: item.title.isEmpty ? "Untitled Task" : item.title,
                isSensitive: SensitiveContentDetector.looksSensitive(item.title)
            ) { displayText in
                Text(displayText)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(item.title.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(2)
            }

            if !item.notes.isEmpty {
                if SensitiveContentDetector.looksSensitive(item.notes) {
                    SensitiveTextReveal(
                        text: item.notes.replacingOccurrences(of: "\n", with: " "),
                        isSensitive: true
                    ) { displayText in
                        Text(displayText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text(MarkdownPreview.render(item.notes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if item.isSensitive {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.shield")
                        Text("SENSITIVE")
                    }
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.pink)
                }

                Text(item.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    // Background Color/Art Palette picker button
                    Button {
                        showBackgroundPicker.toggle()
                    } label: {
                        Image(systemName: "paintpalette")
                            .font(.caption2)
                            .padding(5)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Background options")
                    .popover(isPresented: $showBackgroundPicker, arrowEdge: .bottom) {
                        NoteBackgroundPickerView(
                            selectedColor: item.color,
                            selectedTheme: item.theme,
                            selectedCustomThemeId: item.customThemeId,
                            onSelectColor: { color in
                                onSetColor?(color)
                            },
                            onSelectTheme: { theme in
                                onSetTheme?(theme)
                            },
                            onSelectCustomTheme: { customId in
                                onSetCustomTheme?(customId)
                            }
                        )
                        .padding(4)
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(5)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Delete task")
                }
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
            }
            .frame(height: 24)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            KeepThemeAssets.cardBackground(
                for: item.theme,
                customThemeId: item.customThemeId,
                color: item.color,
                isDark: colorScheme == .dark
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - To Do Editor Component
private struct TodoEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: TodoItem
    let onUpdate: (String, String) -> Void
    let onStatusChange: (TodoStatus) -> Void
    var onSetColor: ((NoteColor) -> Void)? = nil
    var onSetTheme: ((NoteTheme) -> Void)? = nil
    var onSetCustomTheme: ((String?) -> Void)? = nil
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var status: TodoStatus
    @State private var showBackgroundPicker = false
    @State private var saveTask: Task<Void, Never>?

    init(
        item: TodoItem,
        onUpdate: @escaping (String, String) -> Void,
        onStatusChange: @escaping (TodoStatus) -> Void,
        onSetColor: ((NoteColor) -> Void)? = nil,
        onSetTheme: ((NoteTheme) -> Void)? = nil,
        onSetCustomTheme: ((String?) -> Void)? = nil,
        onClose: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onUpdate = onUpdate
        self.onStatusChange = onStatusChange
        self.onSetColor = onSetColor
        self.onSetTheme = onSetTheme
        self.onSetCustomTheme = onSetCustomTheme
        self.onClose = onClose
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes)
        _status = State(initialValue: item.status)
    }

    /// Routes user-driven picker changes to the parent; programmatic resets
    /// (switching the selected task) assign `status` directly instead, so
    /// they don't also fire a redundant status-change callback.\
    private var statusBinding: Binding<TodoStatus> {
        Binding(get: { status }, set: { newValue in
            status = newValue
            onStatusChange(newValue)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Task title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .onChange(of: title) { _, newValue in
                            debounceSave(title: newValue)
                        }

                    AppPillTabs(
                        selection: statusBinding,
                        title: { $0.rawValue }
                    )

                    RichNoteEditor(text: $notes, minHeight: 200)
                        .onChange(of: notes) { _, newValue in
                            debounceSave(notes: newValue)
                        }
                }
                .padding(16)
            }

            footer
        }
        .background(
            KeepThemeAssets.cardBackground(
                for: item.theme,
                customThemeId: item.customThemeId,
                color: item.color,
                isDark: colorScheme == .dark
            )
        )
        .onChange(of: item.id) { _, _ in
            title = item.title
            notes = item.notes
            status = item.status
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(status.color).frame(width: 10, height: 10)
            Text(status.rawValue)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer()

            // Background Theme / Color Picker Button
            Button {
                showBackgroundPicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary)
                    if let customId = item.customThemeId {
                        CustomArtThemeManager.shared.thumbnail(for: customId, isDark: colorScheme == .dark, size: 12)
                    } else if item.theme != .none {
                        KeepThemeAssets.thumbnail(for: item.theme, isDark: colorScheme == .dark, size: 12)
                    } else {
                        Circle()
                            .fill(item.color.swatch)
                            .overlay(Circle().strokeBorder(item.color == .default ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1))
                            .frame(width: 10, height: 10)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Background options")
            .popover(isPresented: $showBackgroundPicker, arrowEdge: .bottom) {
                NoteBackgroundPickerView(
                    selectedColor: item.color,
                    selectedTheme: item.theme,
                    selectedCustomThemeId: item.customThemeId,
                    onSelectColor: { color in
                        onSetColor?(color)
                    },
                    onSelectTheme: { theme in
                        onSetTheme?(theme)
                    },
                    onSelectCustomTheme: { customId in
                        onSetCustomTheme?(customId)
                    }
                )
                .padding(4)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Delete Task")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.primary.opacity(0.04)
        )
    }

    private var footer: some View {
        HStack {
            Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Syncs automatically with Google Drive")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color.primary.opacity(0.04)
        )
    }

    /// Avoids writing to disk and scheduling a Drive sync on every keystroke.
    private func debounceSave(title newTitle: String? = nil, notes newNotes: String? = nil) {
        saveTask?.cancel()
        let pendingTitle = newTitle ?? title
        let pendingNotes = newNotes ?? notes
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            onUpdate(pendingTitle, pendingNotes)
        }
    }
}

// MARK: - Quick Notes: Column 2 (Masonry Gallery Grid)
private struct QuickNotesWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 800
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension ContentView {
    private var quickNotesGrid: some View {
        VStack(spacing: 0) {
            quickNotesHeader

            if filteredNotes.isEmpty {
                quickNotesEmptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !pinnedNotes.isEmpty {
                            quickNoteSectionHeader("PINNED")
                            quickNoteMasonryGrid(pinnedNotes)
                        }
                        if !unpinnedNotes.isEmpty {
                            if !pinnedNotes.isEmpty {
                                quickNoteSectionHeader("OTHERS")
                            }
                            quickNoteMasonryGrid(unpinnedNotes)
                        }
                    }
                    .padding(16)
                    .scrollControlSize(.mini)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: QuickNotesWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(QuickNotesWidthPreferenceKey.self) { newWidth in
                    if newWidth > 50 && abs(quickNotesGridWidth - newWidth) > 5 {
                        quickNotesGridWidth = newWidth
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.primaryBackground)
            }
        }
        .background(Color.primaryBackground)
        .navigationTitle(showArchivedNotes ? "Archived Notes" : "Quick Notes")
    }

    private func quickNoteSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func quickNoteMasonryGrid(_ notes: [QuickNote]) -> some View {
        let contentWidth = max(260, quickNotesGridWidth - 32)
        let columnCount = max(1, min(6, Int((contentWidth + 12) / (240 + 12))))
        let columns = splitNotesIntoColumns(notes, count: columnCount)

        return HStack(alignment: .top, spacing: 12) {
            ForEach(0..<columns.count, id: \.self) { colIndex in
                LazyVStack(spacing: 12) {
                    ForEach(columns[colIndex]) { note in
                        quickNoteCardView(note)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func splitNotesIntoColumns(_ notes: [QuickNote], count: Int) -> [[QuickNote]] {
        guard count > 1 else { return [notes] }
        var result: [[QuickNote]] = Array(repeating: [], count: count)
        for (index, note) in notes.enumerated() {
            result[index % count].append(note)
        }
        return result
    }

    private func quickNoteCardView(_ note: QuickNote) -> some View {
        QuickNoteCard(
            note: note,
            isSelected: selectedNote?.id == note.id,
            onSelect: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedNote = note
                }
            },
            onTogglePin: { quickNoteManager.togglePin(note) },
            onSetColor: { color in quickNoteManager.setColor(note, color: color) },
            onSetTheme: { theme in quickNoteManager.setTheme(note, theme: theme) },
            onSetCustomTheme: { customThemeId in quickNoteManager.setCustomTheme(note, customThemeId: customThemeId) },
            onToggleArchive: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if selectedNote?.id == note.id { selectedNote = nil }
                    quickNoteManager.setArchived(note, isArchived: !note.isArchived)
                }
            },
            onDelete: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if selectedNote?.id == note.id { selectedNote = nil }
                    quickNoteManager.delete(note)
                }
            }
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var quickNotesHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedNote = quickNoteManager.createNote()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("New Note")
                .disabled(showArchivedNotes)
                .opacity(showArchivedNotes ? 0.4 : 1)

                appSearchBar(placeholder: showArchivedNotes ? "Search archived notes..." : "Search notes...")
            }

            AppPillTabs(
                selection: $selectedNoteTab,
                title: { $0.rawValue }
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func appSearchBar(placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                commandKBadge
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
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

    private var quickNotesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: showArchivedNotes ? "archivebox" : "note.text")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(notesEmptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Button("Clear Search") { searchText = "" }
                    .buttonStyle(.bordered)
            } else if !showArchivedNotes {
                Button("New Quick Note") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedNote = quickNoteManager.createNote()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryBackground)
    }

    private var notesEmptyStateTitle: String {
        guard searchText.isEmpty else { return "No results for \"\(searchText)\"" }
        return showArchivedNotes ? "No archived notes" : "No quick notes yet"
    }
}

// MARK: - Quick Note Card Component
private struct QuickNoteCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let note: QuickNote
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onSetColor: (NoteColor) -> Void
    let onSetTheme: (NoteTheme) -> Void
    var onSetCustomTheme: ((String?) -> Void)? = nil
    let onToggleArchive: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false
    @State private var showBackgroundPicker = false

    private let maxVisibleChecklistItems = 5

    private var renderedPreviewText: AttributedString {
        guard !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return AttributedString("Empty note") }
        return MarkdownPreview.render(note.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !note.title.isEmpty {
                SensitiveTextReveal(
                    text: note.title,
                    isSensitive: SensitiveContentDetector.looksSensitive(note.title)
                ) { displayText in
                    Text(displayText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                }
            }

            if note.kind == .checklist {
                checklistPreview
            } else {
                textPreview
            }

            Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 2)

            // Dedicated separate tools row
            HStack(spacing: 6) {
                Button(action: onTogglePin) {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .font(.caption2)
                        .foregroundStyle(note.isPinned ? Color.orange : Color.primary)
                        .padding(5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(note.isPinned ? "Unpin note" : "Pin note")

                colorMenu

                Button(action: onToggleArchive) {
                    Image(systemName: note.isArchived ? "arrow.uturn.backward" : "archivebox")
                        .font(.caption2)
                        .padding(5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(note.isArchived ? "Unarchive note" : "Archive note")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(5)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Delete note")

                Spacer()
            }
            .frame(height: 26)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            KeepThemeAssets.cardBackground(
                for: note.theme,
                customThemeId: note.customThemeId,
                color: note.color,
                isDark: colorScheme == .dark
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            if note.title.isEmpty {
                if note.isSensitive {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.shield")
                        Text("SENSITIVE")
                    }
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.pink)
                } else {
                    Text(note.textContentKind.displayLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(note.textContentKind.color)
                }
            } else if note.isSensitive {
                HStack(spacing: 3) {
                    Image(systemName: "lock.shield")
                    Text("SENSITIVE")
                }
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.pink)
            }

            if note.isSensitive {
                SensitiveTextReveal(
                    text: note.text.replacingOccurrences(of: "\n", with: " "),
                    isSensitive: true
                ) { displayText in
                    Text(displayText)
                        .font(note.textContentKind == .code ? .callout.monospaced() : .callout)
                        .foregroundStyle(Color.primary)
                        .lineLimit(5)
                        .truncationMode(.tail)
                }
            } else if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Empty note")
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
            } else if note.textContentKind == .code {
                Text(note.text)
                    .font(.callout.monospaced())
                    .foregroundStyle(Color.primary)
                    .lineLimit(5)
                    .truncationMode(.tail)
            } else {
                Text(renderedPreviewText)
                    .font(.callout)
                    .foregroundStyle(Color.primary)
                    .lineLimit(5)
                    .truncationMode(.tail)
            }
        }
    }

    private var checklistPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if note.isSensitive {
                HStack(spacing: 3) {
                    Image(systemName: "lock.shield")
                    Text("SENSITIVE")
                }
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.pink)
                .padding(.bottom, 2)
            }

            ForEach(note.checklistItems.prefix(maxVisibleChecklistItems)) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                        .font(.caption)
                        .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)
                    SensitiveTextReveal(
                        text: item.text.isEmpty ? "Empty item" : item.text,
                        isSensitive: SensitiveContentDetector.looksSensitive(item.text)
                    ) { displayText in
                        Text(displayText)
                            .font(.callout)
                            .foregroundStyle(item.isChecked ? Color.secondary : Color.primary)
                            .strikethrough(item.isChecked)
                            .lineLimit(1)
                    }
                }
            }
            if note.checklistItems.count > maxVisibleChecklistItems {
                Text("+ \(note.checklistItems.count - maxVisibleChecklistItems) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var colorMenu: some View {
        Button {
            showBackgroundPicker.toggle()
        } label: {
            Image(systemName: "paintpalette")
                .font(.caption2)
                .padding(5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Background options")
        .popover(isPresented: $showBackgroundPicker, arrowEdge: .bottom) {
            NoteBackgroundPickerView(
                selectedColor: note.color,
                selectedTheme: note.theme,
                selectedCustomThemeId: note.customThemeId,
                onSelectColor: { color in
                    onSetColor(color)
                },
                onSelectTheme: { theme in
                    onSetTheme(theme)
                },
                onSelectCustomTheme: { customId in
                    onSetCustomTheme?(customId)
                }
            )
            .padding(4)
        }
    }
}

// MARK: - Quick Note Editor Component
private struct QuickNoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme

    let note: QuickNote
    let onUpdateText: (String, String) -> Void
    let onUpdateChecklist: (String, [ChecklistItem]) -> Void
    let onTogglePin: () -> Void
    let onSetColor: (NoteColor) -> Void
    let onSetTheme: (NoteTheme) -> Void
    var onSetCustomTheme: ((String?) -> Void)? = nil
    let onToggleArchive: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var text: String
    @State private var checklistItems: [ChecklistItem]
    @State private var kind: QuickNoteKind
    @State private var isCompletedExpanded = true
    @State private var showBackgroundPicker = false
    @State private var editorProxy = RichNoteEditorProxy()
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focusedChecklistItemID: String?

    init(
        note: QuickNote,
        onUpdateText: @escaping (String, String) -> Void,
        onUpdateChecklist: @escaping (String, [ChecklistItem]) -> Void,
        onTogglePin: @escaping () -> Void,
        onSetColor: @escaping (NoteColor) -> Void,
        onSetTheme: @escaping (NoteTheme) -> Void,
        onSetCustomTheme: ((String?) -> Void)? = nil,
        onToggleArchive: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.note = note
        self.onUpdateText = onUpdateText
        self.onUpdateChecklist = onUpdateChecklist
        self.onTogglePin = onTogglePin
        self.onSetColor = onSetColor
        self.onSetTheme = onSetTheme
        self.onSetCustomTheme = onSetCustomTheme
        self.onToggleArchive = onToggleArchive
        self.onClose = onClose
        self.onDelete = onDelete
        _title = State(initialValue: note.title)
        _text = State(initialValue: note.text)
        _checklistItems = State(initialValue: note.checklistItems)
        _kind = State(initialValue: note.kind)
    }

    private var liveKind: ClipboardContentKind {
        ClipboardContentKind.detect(from: text)
    }

    private var liveLink: URL? {
        guard !text.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, range: range) else { return nil }
        return match.url
    }

    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .onChange(of: title) { _, newValue in
                            debounceSave(title: newValue)
                        }

                    if kind == .checklist {
                        checklistEditor
                    } else {
                        RichNoteEditor(text: $text, usesMonospacedFont: liveKind == .code, proxy: editorProxy)
                            .onChange(of: text) { _, newValue in
                                debounceSave(text: newValue)
                            }

                        if let liveLink {
                            linkActionBanner(url: liveLink)
                        }

                        if liveKind == .code {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Preview")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                CodeBlockView(code: text)
                            }
                        }
                    }
                }
                .padding(16)
            }

            footer
        }
        .background(
            KeepThemeAssets.cardBackground(
                for: note.theme,
                customThemeId: note.customThemeId,
                color: note.color,
                isDark: colorScheme == .dark
            )
        )
        .onChange(of: note.id) { _, _ in
            title = note.title
            text = note.text
            checklistItems = note.checklistItems
            kind = note.kind
        }
    }

    private func linkActionBanner(url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Link Detected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Open") {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var checklistEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active (unchecked) checklist items
            VStack(alignment: .leading, spacing: 2) {
                ForEach($checklistItems) { $item in
                    if !item.isChecked {
                        checklistItemRow(item: $item)
                    }
                }
            }

            // Google Keep style "+ List item" button
            Button {
                addChecklistItem(after: checklistItems.last?.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text("List item")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            // Completed / Checked items section
            let checkedItems = checklistItems.filter { $0.isChecked }
            if !checkedItems.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                DisclosureGroup(isExpanded: $isCompletedExpanded) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach($checklistItems) { $item in
                            if item.isChecked {
                                checklistItemRow(item: $item)
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(checkedItems.count) Completed items")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func checklistItemRow(item: Binding<ChecklistItem>) -> some View {
        ChecklistItemRowView(
            item: item,
            isFocused: focusedChecklistItemID == item.wrappedValue.id,
            onFocus: { focusedChecklistItemID = item.wrappedValue.id },
            onCommit: { addChecklistItem(after: item.wrappedValue.id) },
            onDelete: { removeChecklistItem(item.wrappedValue.id) },
            onChange: { debounceSave(checklist: checklistItems) }
        )
    }

    private var header: some View {
        VStack(spacing: 0) {
            // Row 1: Header metadata & main controls
            HStack(spacing: 8) {
                Image(systemName: kind == .checklist ? "checklist" : liveKind.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)

                Text("Updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                headerSquareButton(icon: note.isPinned ? "pin.fill" : "pin", color: note.isPinned ? Color.orange : Color.primary, tooltip: note.isPinned ? "Unpin note" : "Pin note", action: onTogglePin)

                headerSquareButton(icon: note.isArchived ? "arrow.uturn.backward" : "archivebox", tooltip: note.isArchived ? "Unarchive note" : "Archive note", action: onToggleArchive)

                headerSquareButton(icon: "trash", tooltip: "Delete Note", action: onDelete)

                headerSquareButton(icon: "xmark", tooltip: "Close", action: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Row 2: Formatting & editing tools toolbar
            toolsRow
        }
        .background(
            Color.primary.opacity(0.04)
        )
    }

    private var kindSelection: Binding<QuickNoteKind> {
        Binding(get: { kind }, set: { switchKind(to: $0) })
    }

    private func switchKind(to newKind: QuickNoteKind) {
        guard newKind != kind else { return }
        if newKind == .text {
            text = checklistItems.map { $0.text }.filter { !$0.isEmpty }.joined(separator: "\n")
            kind = .text
            QuickNoteManager.shared.convertToText(note)
        } else {
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            checklistItems = lines.isEmpty ? [ChecklistItem()] : lines.map { ChecklistItem(text: $0) }
            kind = .checklist
            QuickNoteManager.shared.convertToChecklist(note)
        }
    }

    private var toolsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                AppPillTabs(
                    selection: kindSelection,
                    items: [QuickNoteKind.text, .checklist],
                    title: { $0 == .text ? "Text" : "Check List" },
                    icon: { $0 == .text ? "text.alignleft" : "checklist" },
                    isCompact: true
                )
                .frame(width: 190)

                toolbarDivider

                // MARK: - Color & Background Theme Picker
                Button {
                    showBackgroundPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary)
                        if let customId = note.customThemeId {
                            CustomArtThemeManager.shared.thumbnail(for: customId, isDark: colorScheme == .dark, size: 12)
                        } else if note.theme != .none {
                            KeepThemeAssets.thumbnail(for: note.theme, isDark: colorScheme == .dark, size: 12)
                        } else {
                            Circle()
                                .fill(note.color.swatch)
                                .overlay(Circle().strokeBorder(note.color == .default ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1))
                                .frame(width: 10, height: 10)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Background options")
                .popover(isPresented: $showBackgroundPicker, arrowEdge: .bottom) {
                    NoteBackgroundPickerView(
                        selectedColor: note.color,
                        selectedTheme: note.theme,
                        selectedCustomThemeId: note.customThemeId,
                        onSelectColor: { color in
                            onSetColor(color)
                        },
                        onSelectTheme: { theme in
                            onSetTheme(theme)
                        },
                        onSelectCustomTheme: { customId in
                            onSetCustomTheme?(customId)
                        }
                    )
                    .padding(4)
                }

                toolbarDivider

                // MARK: - Extra Tools (Link, Timestamp, Divider)
                Group {
                    toolButton(icon: "link", tooltip: "Insert Link") {
                        applyInline(.link) { insertMarkdown(prefix: "[", suffix: "](https://)", placeholder: "link text") }
                    }
                    toolButton(icon: "clock", tooltip: "Insert Timestamp") {
                        let timestamp = Date().formatted(date: .abbreviated, time: .shortened)
                        if kind == .text {
                            editorProxy.insertText(timestamp)
                        } else {
                            insertMarkdown(prefix: timestamp)
                        }
                    }
                    toolButton(icon: "divide", tooltip: "Insert Line Divider") {
                        applyBlock(.divider) { insertMarkdown(prefix: "---") }
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 14)
            .padding(.horizontal, 2)
    }

    private func headerSquareButton(icon: String, color: Color = Color.primary, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func toolButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    /// Text notes format through the live editor; checklist notes keep the raw-insert fallback.
    private func applyBlock(_ type: NoteBlockType, checklistFallback: () -> Void) {
        if kind == .text {
            editorProxy.applyBlock(type)
        } else {
            checklistFallback()
        }
    }

    private func applyInline(_ format: NoteInlineFormat, checklistFallback: () -> Void) {
        if kind == .text {
            editorProxy.apply(format)
        } else {
            checklistFallback()
        }
    }

    private func insertMarkdown(prefix: String, suffix: String = "", placeholder: String = "") {
        if kind == .checklist {
            if let focusedID = focusedChecklistItemID,
               let index = checklistItems.firstIndex(where: { $0.id == focusedID }) {
                let current = checklistItems[index].text
                let content = placeholder.isEmpty ? "" : placeholder
                checklistItems[index].text = current.isEmpty ? "\(prefix)\(content)\(suffix)" : "\(current) \(prefix)\(content)\(suffix)"
                debounceSave(checklist: checklistItems)
            } else {
                let content = placeholder.isEmpty ? "" : placeholder
                let newItem = ChecklistItem(text: "\(prefix)\(content)\(suffix)")
                checklistItems.append(newItem)
                debounceSave(checklist: checklistItems)
                focusedChecklistItemID = newItem.id
            }
            return
        }

        let content = placeholder.isEmpty ? "" : placeholder
        if text.isEmpty {
            text = "\(prefix)\(content)\(suffix)"
        } else {
            let isBlockLevel = prefix.hasPrefix("#") || prefix.hasPrefix("• ") || prefix.hasPrefix("1. ") || prefix.hasPrefix("- [ ] ") || prefix.hasPrefix("> ") || prefix.hasPrefix("---")
            if isBlockLevel {
                let separator = text.hasSuffix("\n") ? "" : "\n"
                text += "\(separator)\(prefix)\(content)\(suffix)"
            } else {
                let separator = text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
                text += "\(separator)\(prefix)\(content)\(suffix)"
            }
        }
        debounceSave(text: text)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if kind == .checklist {
                metaBadge(title: "Checked", value: "\(checklistItems.filter { $0.isChecked }.count)/\(checklistItems.count)")
            } else {
                metaBadge(title: "Characters", value: "\(text.count)")
                metaBadge(title: "Words", value: "\(wordCount)")
            }
            Spacer()
            Text("Syncs automatically with Google Drive")
                .font(.caption2)
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

    private func addChecklistItem(after id: String?) {
        let newItem = ChecklistItem()
        if let id, let index = checklistItems.firstIndex(where: { $0.id == id }) {
            checklistItems.insert(newItem, at: index + 1)
        } else {
            checklistItems.append(newItem)
        }
        debounceSave(checklist: checklistItems)
        focusedChecklistItemID = newItem.id
    }

    private func removeChecklistItem(_ id: String) {
        checklistItems.removeAll { $0.id == id }
        debounceSave(checklist: checklistItems)
    }

    /// Avoids writing to disk and scheduling a Drive sync on every keystroke/toggle.
    private func debounceSave(title newTitle: String? = nil, text newText: String? = nil, checklist newChecklist: [ChecklistItem]? = nil) {
        saveTask?.cancel()
        let pendingTitle = newTitle ?? title
        let pendingText = newText ?? text
        let pendingChecklist = newChecklist ?? checklistItems
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if kind == .checklist {
                onUpdateChecklist(pendingTitle, pendingChecklist)
            } else {
                onUpdateText(pendingTitle, pendingText)
            }
        }
    }
}

// MARK: - Google Keep Style Checklist Item Row
private struct ChecklistItemRowView: View {
    @Binding var item: ChecklistItem
    let isFocused: Bool
    let onFocus: () -> Void
    let onCommit: () -> Void
    let onDelete: () -> Void
    let onChange: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // 6-dot drag handle (Google Keep style)
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.primary.opacity(isHovering ? 0.8 : 0.45))
                .frame(width: 14)
                .contentShape(Rectangle())

            // Checkbox
            Button {
                item.isChecked.toggle()
                onChange()
            } label: {
                Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isChecked ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)

            // Editable text
            TextField("List item", text: $item.text)
                .textFieldStyle(.plain)
                .font(.body)
                .strikethrough(item.isChecked)
                .foregroundStyle(item.isChecked ? Color.secondary : Color.primary)
                .onSubmit {
                    onCommit()
                }
                .onChange(of: item.text) { _, _ in
                    onChange()
                }

            // Delete button on hover
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .padding(4)
                    .background(Color.primary.opacity(isHovering ? 0.08 : 0), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Delete item")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - App Clipboard Card Component
private struct AppClipboardCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
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
                            .fixedSize()
                    } else {
                        Text(item.contentKind.displayLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(item.contentKind.color)
                            .fixedSize()
                    }

                    Spacer(minLength: 8)

                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }

                SensitiveTextReveal(
                    text: item.text.replacingOccurrences(of: "\n", with: " "),
                    isSensitive: item.isSensitive
                ) { displayText in
                    Text(displayText)
                        .font(item.contentKind == .code ? .callout.monospaced() : .callout)
                        .foregroundStyle(item.contentKind == .code ? item.contentKind.color : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 6) {
                    Text("\(item.text.count) chars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())

                    Spacer()

                    if isHovering || isSelected || item.isPinned {
                        HStack(spacing: 4) {
                            Button(action: onTogglePin) {
                                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                    .font(.caption2)
                                    .foregroundStyle(item.isPinned ? Color.orange : Color.secondary)
                                    .padding(5)
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help(item.isPinned ? "Unpin item" : "Pin item")

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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.background), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : (item.isPinned ? Color.orange.opacity(0.4) : Color.clear), lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0), radius: 8, y: 2)
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
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - App Detail Inspector View Component
private struct AppDetailInspectorView: View {
    let item: ClipboardItem
    let onTogglePin: () -> Void
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let colorInfo = item.detectedColor {
                        inspectorColorPaletteSection(colorInfo)
                    }

                    if item.contentKind == .link, let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        linkActionBanner(url: url)
                    }

                    transformSection

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
                        }
                    }
                }
                .padding(16)
                .scrollControlSize(.mini)
            }

            inspectorFooter
        }
    }

    private var inspectorHeader: some View {
        HStack(spacing: 12) {
            if let colorInfo = item.detectedColor {
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorInfo.color)
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(item.contentKind.color)
                        .frame(width: 32, height: 32)
                    Image(systemName: item.contentKind.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.detectedColor != nil ? "Color Code" : item.contentKind.displayLabel)
                        .font(.headline)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text("Copied \(item.date.formatted(date: .complete, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.isPinned ? Color.orange : Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin Item" : "Pin Item")

                Button {
                    onCopy()
                    withAnimation(.snappy) { didCopy = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.snappy) { didCopy = false }
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(didCopy ? Color.white : Color.primary)
                        .frame(width: 28, height: 28)
                        .background(didCopy ? Color.accentColor : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(didCopy ? "Copied!" : "Copy to Clipboard (⌘C)")
                .keyboardShortcut("c", modifiers: .command)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Delete item")
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.primary.opacity(0.04)
        )
    }

    private var transformSection: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Color.accentColor)
            Text("Transform & Format Content")
                .font(.callout)
                .fontWeight(.medium)

            Spacer()

            Menu {
                ForEach(TextTransformer.Action.allCases) { action in
                    Button {
                        if let res = TextTransformer.transform(item.text, using: action) {
                            ClipboardManager.shared.copyRawText(res)
                        }
                    } label: {
                        Label(action.rawValue, systemImage: action.iconName)
                    }
                }
            } label: {
                Text("Select Action...")
                    .font(.caption)
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private func inspectorColorPaletteSection(_ colorInfo: DetectedColor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorInfo.color)
                    .frame(width: 48, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Detected Color Swatch")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Click any format to copy directly")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                inspectorFormatBtn(title: "HEX", value: colorInfo.hexString)
                inspectorFormatBtn(title: "RGB", value: colorInfo.rgbString)
                inspectorFormatBtn(title: "HSL", value: colorInfo.hslString)
                inspectorFormatBtn(title: "SwiftUI", value: colorInfo.swiftUIString)
                inspectorFormatBtn(title: "NSColor", value: colorInfo.nsColorCodeString)
            }
        }
        .padding(12)
        .background(Color.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func inspectorFormatBtn(title: String, value: String) -> some View {
        Button {
            ClipboardManager.shared.copyRawText(value)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
    }

    private var inspectorFooter: some View {
        HStack(spacing: 16) {
            metaBadge(title: "Characters", value: "\(item.text.count)")
            metaBadge(title: "Words", value: "\(wordCount)")
            metaBadge(title: "Lines", value: "\(lineCount)")
            Spacer()
            Text("ID: \(item.id.prefix(8))")
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

// MARK: - Content Filter Model
enum ContentFilter: String, CaseIterable, Identifiable {
    case all = "All Items"
    case pinned = "Pinned Items"
    case text = "Plain Text"
    case code = "Code Snippets"
    case link = "Web Links"
    case color = "Colors"
    case sensitive = "Sensitive Data"

    var id: String { rawValue }
    var title: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "tray.full"
        case .pinned: return "pin.fill"
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .sensitive: return "lock.shield.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .all: return .primary
        case .pinned: return .orange
        case .text: return .blue
        case .code: return .purple
        case .link: return .green
        case .color: return .pink
        case .sensitive: return .red
        }
    }
}

/// Hides the native macOS hairline drawn between the titlebar/toolbar and the
/// content below, without touching the toolbar's background material.
private struct TitlebarSeparatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            hideSeparators(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            hideSeparators(from: nsView)
        }
    }

    /// `NSWindow.titlebarSeparatorStyle` only covers the window's own title bar; a
    /// `NavigationSplitView` is backed by an `NSSplitViewController` whose individual
    /// `NSSplitViewItem`s draw their own hairline under each column's inline title,
    /// so both need to be silenced.
    private func hideSeparators(from view: NSView) {
        guard let window = view.window else { return }
        window.titlebarSeparatorStyle = .none
        if let splitViewController = window.contentViewController as? NSSplitViewController {
            for item in splitViewController.splitViewItems {
                item.titlebarSeparatorStyle = .none
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(ClipboardManager.shared)
}
