//
//  NoteEditorMenus.swift
//  SyncBoard
//

import AppKit
import SwiftUI

// MARK: - Block Types

enum NoteBlockType: String, CaseIterable, Identifiable {
    case text
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case todo
    case quote
    case codeBlock
    case divider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulletList: return "Bulleted list"
        case .numberedList: return "Numbered list"
        case .todo: return "To-do list"
        case .quote: return "Quote"
        case .codeBlock: return "Code block"
        case .divider: return "Divider"
        }
    }

    var subtitle: String {
        switch self {
        case .text: return "Plain paragraph"
        case .heading1: return "Big section heading"
        case .heading2: return "Medium section heading"
        case .heading3: return "Small section heading"
        case .bulletList: return "Simple bulleted list"
        case .numberedList: return "List with numbering"
        case .todo: return "Track tasks with checkboxes"
        case .quote: return "Capture a quote"
        case .codeBlock: return "Monospaced code snippet"
        case .divider: return "Visually separate blocks"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "textformat"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .heading3: return "textformat.size.smaller"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .todo: return "checklist"
        case .quote: return "quote.opening"
        case .codeBlock: return "chevron.left.forwardslash.chevron.right"
        case .divider: return "minus"
        }
    }

    private var keywords: [String] {
        switch self {
        case .text: return ["paragraph", "plain", "p"]
        case .heading1: return ["h1", "title"]
        case .heading2: return ["h2", "subtitle"]
        case .heading3: return ["h3"]
        case .bulletList: return ["ul", "unordered", "bullet"]
        case .numberedList: return ["ol", "ordered", "number"]
        case .todo: return ["todo", "checkbox", "task", "check"]
        case .quote: return ["blockquote", "citation"]
        case .codeBlock: return ["code", "snippet", "pre"]
        case .divider: return ["hr", "line", "separator", "rule"]
        }
    }

    /// Markdown prefix for line-level blocks; divider and code block are multi-line.
    var linePrefix: String {
        switch self {
        case .text, .divider, .codeBlock: return ""
        case .heading1: return "# "
        case .heading2: return "## "
        case .heading3: return "### "
        case .bulletList: return "- "
        case .numberedList: return "1. "
        case .todo: return "- [ ] "
        case .quote: return "> "
        }
    }

    var isListType: Bool {
        self == .bulletList || self == .numberedList || self == .todo
    }

    static func matching(_ query: String) -> [NoteBlockType] {
        let query = query.lowercased()
        guard !query.isEmpty else { return allCases }
        return allCases.filter { type in
            let words = type.title.lowercased().split(separator: " ").map(String.init) + type.keywords
            return words.contains { $0.hasPrefix(query) } || type.title.lowercased().hasPrefix(query)
        }
    }
}

// MARK: - Inline Formats

enum NoteInlineFormat: String, CaseIterable, Identifiable {
    case bold
    case italic
    case strikethrough
    case code
    case link

    var id: String { rawValue }

    var marker: String {
        switch self {
        case .bold: return "**"
        case .italic: return "*"
        case .strikethrough: return "~~"
        case .code: return "`"
        case .link: return ""
        }
    }

    var iconName: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        }
    }

    var help: String {
        switch self {
        case .bold: return "Bold (⌘B)"
        case .italic: return "Italic (⌘I)"
        case .strikethrough: return "Strikethrough (⇧⌘X)"
        case .code: return "Inline code (⌘E)"
        case .link: return "Link (⌘K)"
        }
    }
}

// MARK: - Floating Panel

/// Borderless panel that never becomes key, so the note's text view keeps
/// keyboard focus while a slash or bubble menu is on screen.
final class NoteFloatingPanel: NSPanel {
    private let hostingView = FirstMouseHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `anchor` is in screen coordinates; the panel opens below it unless
    /// `preferAbove` is set or there isn't room on screen.
    func present(_ content: AnyView, anchor: NSRect, parentWindow: NSWindow, preferAbove: Bool = false) {
        hostingView.rootView = content
        let size = hostingView.fittingSize
        let gap: CGFloat = 6
        let screenFrame = parentWindow.screen?.visibleFrame ?? .infinite

        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - gap)
        let aboveY = anchor.maxY + gap
        if preferAbove, aboveY + size.height <= screenFrame.maxY {
            origin.y = aboveY
        } else if origin.y < screenFrame.minY {
            origin.y = aboveY
        }
        origin.x = min(max(origin.x, screenFrame.minX + gap), screenFrame.maxX - size.width - gap)

        setFrame(NSRect(origin: origin, size: size), display: true)
        if parent !== parentWindow {
            parent?.removeChildWindow(self)
            parentWindow.addChildWindow(self, ordered: .above)
        }
        orderFront(nil)
    }

    func dismiss() {
        guard isVisible || parent != nil else { return }
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Slash Command Menu

struct SlashCommandMenu: View {
    let items: [NoteBlockType]
    let selectedIndex: Int
    let onSelect: (NoteBlockType) -> Void

    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Basic blocks")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, isSelected: index == selectedIndex)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .onAppear { scrollToSelection(proxy) }
                .onChange(of: selectedIndex) { _, _ in scrollToSelection(proxy) }
            }
            .frame(height: min(CGFloat(items.count), 6.5) * rowHeight + 6)
        }
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard items.indices.contains(selectedIndex) else { return }
        proxy.scrollTo(items[selectedIndex].id)
    }

    private func row(_ item: NoteBlockType, isSelected: Bool) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Formatting Bubble Menu

struct FormattingBubbleMenu: View {
    let activeFormats: Set<NoteInlineFormat>
    let activeBlock: NoteBlockType?
    let onFormat: (NoteInlineFormat) -> Void
    let onBlock: (NoteBlockType) -> Void

    private let blockTypes: [NoteBlockType] = [.heading1, .heading2, .bulletList, .todo, .quote]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NoteInlineFormat.allCases) { format in
                button(icon: format.iconName, help: format.help, isActive: activeFormats.contains(format)) {
                    onFormat(format)
                }
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)

            ForEach(blockTypes) { type in
                button(icon: type.iconName, help: "Turn into \(type.title.lowercased())", isActive: activeBlock == type) {
                    onBlock(activeBlock == type ? .text : type)
                }
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func button(icon: String, help: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
