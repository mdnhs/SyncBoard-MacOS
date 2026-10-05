//
//  RichNoteEditor.swift
//  SyncBoard
//

import AppKit
import SwiftUI

// MARK: - Markdown Line Model

/// One parsed line of a note's markdown. Ranges are UTF-16 based so they map
/// directly onto `NSString`/`NSTextStorage` offsets.
struct NoteLine: Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading(level: Int)
        case bullet
        case numbered(Int)
        case task(isChecked: Bool)
        case quote
        case divider
    }

    let kind: Kind
    let indentLength: Int
    let indentLevel: Int
    /// Length of the block marker after the indent, including its trailing space.
    let markerLength: Int

    static func parse(_ line: String) -> NoteLine {
        let ns = line as NSString
        var indentLength = 0
        var indentUnits = 0
        while indentLength < ns.length {
            let char = ns.character(at: indentLength)
            if char == 0x20 {
                indentUnits += 1
            } else if char == 0x09 {
                indentUnits += 2
            } else {
                break
            }
            indentLength += 1
        }
        let level = indentUnits / 2
        let rest = ns.substring(from: indentLength)

        func result(_ kind: Kind, _ markerLength: Int) -> NoteLine {
            NoteLine(kind: kind, indentLength: indentLength, indentLevel: level, markerLength: markerLength)
        }

        if indentLength == 0, ["---", "***", "___"].contains(rest.trimmingCharacters(in: .whitespaces)) {
            return result(.divider, ns.length)
        }

        let hashes = rest.prefix { $0 == "#" }.count
        if (1...3).contains(hashes), rest.dropFirst(hashes).first == " " {
            return result(.heading(level: hashes), hashes + 1)
        }

        let chars = Array(rest.utf16.prefix(6))
        let isBulletChar = chars.first.map { [0x2D, 0x2A, 0x2022].contains($0) } ?? false
        if isBulletChar, chars.count >= 2, chars[1] == 0x20 {
            let taskTail = String(utf16CodeUnits: Array(chars.dropFirst(2)), count: max(0, chars.count - 2))
            if taskTail == "[ ] " {
                return result(.task(isChecked: false), 6)
            }
            if taskTail == "[x] " || taskTail == "[X] " {
                return result(.task(isChecked: true), 6)
            }
            return result(.bullet, 2)
        }

        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 4 {
            let afterDigits = rest.dropFirst(digits.count)
            if let punctuation = afterDigits.first, punctuation == "." || punctuation == ")",
               afterDigits.dropFirst().first == " ", let number = Int(digits) {
                return result(.numbered(number), digits.count + 2)
            }
        }

        if rest.hasPrefix("> ") {
            return result(.quote, 2)
        }

        return result(.paragraph, 0)
    }
}

// MARK: - Custom Attributes

extension NSAttributedString.Key {
    static let noteBlock = NSAttributedString.Key("SyncBoard.noteBlock")
    static let noteCheckbox = NSAttributedString.Key("SyncBoard.noteCheckbox")
}

enum NoteBlockDecoration: Int {
    case bullet
    case quote
    case divider
    case codeBlock
}

// MARK: - Styler

/// Re-derives every display attribute from the raw markdown on each edit.
/// Notes are small, so a full pass is cheap and keeps multi-line state
/// (code fences) correct without incremental bookkeeping.
@MainActor
final class NoteMarkdownStyler {
    var usesMonospacedFont = false

    private static let inlineCodePattern = try? NSRegularExpression(pattern: "`([^`\\n]+)`")
    private static let boldPattern = try? NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italicPattern = try? NSRegularExpression(pattern: "(?<![\\*\\w])([\\*_])(?![\\*_\\s])(.+?)(?<![\\*_\\s])\\1(?![\\*\\w])")
    private static let strikePattern = try? NSRegularExpression(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let linkPattern = try? NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)")
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static let indentWidth: CGFloat = 20
    private static let bulletMarkerWidth: CGFloat = 18
    private static let taskMarkerWidth: CGFloat = 24
    private static let numberMarkerWidth: CGFloat = 22
    private static let blockInset: CGFloat = 12

    var baseFont: NSFont {
        let size = NSFont.preferredFont(forTextStyle: .body).pointSize + 1
        return usesMonospacedFont
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)
    }

    private var codeFont: NSFont {
        .monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    /// `activeRange` is the paragraph range holding the caret; markdown markers
    /// inside it stay visible (dimmed) so they can be edited, others collapse.
    func style(_ storage: NSTextStorage, revealing activeRange: NSRange?) {
        let text = storage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        guard fullRange.length > 0 else { return }

        storage.setAttributes(baseAttributes, range: fullRange)

        var isInsideFence = false
        text.enumerateSubstrings(in: fullRange, options: [.byParagraphs, .substringNotRequired]) { _, lineRange, enclosingRange, _ in
            let isActive = activeRange.map { NSIntersectionRange(enclosingRange, $0).length > 0 } ?? false
            let line = text.substring(with: lineRange)

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInsideFence.toggle()
                self.styleCode(storage, lineRange: lineRange, enclosingRange: enclosingRange, isFence: true)
                return
            }
            if isInsideFence {
                self.styleCode(storage, lineRange: lineRange, enclosingRange: enclosingRange, isFence: false)
                return
            }

            let parsed = NoteLine.parse(line)
            self.styleBlock(parsed, in: storage, lineRange: lineRange, enclosingRange: enclosingRange, isActive: isActive)

            guard parsed.kind != .divider else { return }
            let contentStart = lineRange.location + parsed.indentLength + parsed.markerLength
            let contentRange = NSRange(location: contentStart, length: NSMaxRange(lineRange) - contentStart)
            if contentRange.length > 0 {
                self.styleInline(storage, text: storage.string, in: contentRange, reveal: isActive)
            }
        }
    }

    // MARK: Blocks

    private func styleBlock(_ line: NoteLine, in storage: NSTextStorage, lineRange: NSRange, enclosingRange: NSRange, isActive: Bool) {
        let indentRange = NSRange(location: lineRange.location, length: line.indentLength)
        let markerRange = NSRange(location: NSMaxRange(indentRange), length: line.markerLength)
        let contentRange = NSRange(location: NSMaxRange(markerRange), length: NSMaxRange(lineRange) - NSMaxRange(markerRange))
        let indent = CGFloat(line.indentLevel) * Self.indentWidth
        collapse(storage, range: indentRange)

        switch line.kind {
        case .paragraph:
            if indent > 0 {
                storage.addAttribute(.paragraphStyle, value: paragraphStyle(firstIndent: indent, headIndent: indent), range: enclosingRange)
            }

        case .heading(let level):
            let sizes: [CGFloat] = [baseFont.pointSize + 9, baseFont.pointSize + 5, baseFont.pointSize + 2]
            let weight: NSFont.Weight = level == 3 ? .semibold : .bold
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: sizes[level - 1], weight: weight), range: lineRange)
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(firstIndent: indent, headIndent: indent, spacingBefore: level == 1 ? 10 : 6), range: enclosingRange)
            styleMarker(storage, range: markerRange, reveal: isActive)

        case .bullet:
            hide(storage, range: markerRange)
            storage.addAttribute(.noteBlock, value: NoteBlockDecoration.bullet.rawValue, range: markerRange)
            setWidth(storage, range: markerRange, to: Self.bulletMarkerWidth)
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(firstIndent: indent, headIndent: indent + Self.bulletMarkerWidth, spacing: 2), range: enclosingRange)

        case .task(let isChecked):
            hide(storage, range: markerRange)
            storage.addAttribute(.noteCheckbox, value: isChecked, range: markerRange)
            setWidth(storage, range: markerRange, to: Self.taskMarkerWidth)
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(firstIndent: indent, headIndent: indent + Self.taskMarkerWidth, spacing: 2), range: enclosingRange)
            if isChecked, contentRange.length > 0 {
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.secondaryLabelColor
                ], range: contentRange)
            }

        case .numbered:
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.monospacedDigitSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            ], range: markerRange)
            let natural = storage.attributedSubstring(from: markerRange).size().width
            let width = max(Self.numberMarkerWidth, ceil(natural))
            setWidth(storage, range: markerRange, to: width)
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(firstIndent: indent, headIndent: indent + width, spacing: 2), range: enclosingRange)

        case .quote:
            styleMarker(storage, range: markerRange, reveal: isActive)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: contentRange)
            storage.addAttribute(.noteBlock, value: NoteBlockDecoration.quote.rawValue, range: enclosingRange)
            let quoteIndent = indent + Self.blockInset
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(firstIndent: quoteIndent, headIndent: quoteIndent, spacing: 2), range: enclosingRange)

        case .divider:
            if isActive {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lineRange)
            } else {
                collapse(storage, range: lineRange)
                storage.addAttribute(.noteBlock, value: NoteBlockDecoration.divider.rawValue, range: lineRange)
            }
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(spacingBefore: 6, spacing: 10), range: enclosingRange)
        }
    }

    private func styleCode(_ storage: NSTextStorage, lineRange: NSRange, enclosingRange: NSRange, isFence: Bool) {
        storage.addAttributes([
            .font: isFence ? NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 3, weight: .medium) : codeFont,
            .foregroundColor: isFence ? NSColor.tertiaryLabelColor : NSColor.labelColor,
            .noteBlock: NoteBlockDecoration.codeBlock.rawValue,
            .paragraphStyle: paragraphStyle(firstIndent: Self.blockInset, headIndent: Self.blockInset, tailIndent: -Self.blockInset, spacing: 0)
        ], range: enclosingRange)
    }

    // MARK: Inline

    private func styleInline(_ storage: NSTextStorage, text: String, in range: NSRange, reveal: Bool) {
        var protectedRanges: [NSRange] = []
        func isProtected(_ candidate: NSRange) -> Bool {
            protectedRanges.contains { NSIntersectionRange($0, candidate).length > 0 }
        }

        Self.inlineCodePattern?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            let whole = match.range
            protectedRanges.append(whole)
            storage.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.labelColor.withAlphaComponent(0.07)
            ], range: match.range(at: 1))
            styleMarker(storage, range: NSRange(location: whole.location, length: 1), reveal: reveal)
            styleMarker(storage, range: NSRange(location: NSMaxRange(whole) - 1, length: 1), reveal: reveal)
        }

        Self.linkPattern?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, !isProtected(match.range) else { return }
            let whole = match.range
            let label = match.range(at: 1)
            protectedRanges.append(whole)
            if let url = URL(string: (text as NSString).substring(with: match.range(at: 2))) {
                storage.addAttribute(.link, value: url, range: label)
            }
            styleMarker(storage, range: NSRange(location: whole.location, length: 1), reveal: reveal)
            styleMarker(storage, range: NSRange(location: NSMaxRange(label), length: NSMaxRange(whole) - NSMaxRange(label)), reveal: reveal)
        }

        Self.linkDetector?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let url = match.url, !isProtected(match.range) else { return }
            storage.addAttribute(.link, value: url, range: match.range)
        }

        applyDelimited(Self.boldPattern, contentGroup: 2, markerLength: 2, in: storage, text: text, range: range, reveal: reveal, isProtected: isProtected) {
            self.addTrait(.boldFontMask, to: storage, range: $0)
        }
        applyDelimited(Self.italicPattern, contentGroup: 2, markerLength: 1, in: storage, text: text, range: range, reveal: reveal, isProtected: isProtected) {
            self.addTrait(.italicFontMask, to: storage, range: $0)
        }
        applyDelimited(Self.strikePattern, contentGroup: 1, markerLength: 2, in: storage, text: text, range: range, reveal: reveal, isProtected: isProtected) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: $0)
        }
    }

    private func applyDelimited(
        _ pattern: NSRegularExpression?,
        contentGroup: Int,
        markerLength: Int,
        in storage: NSTextStorage,
        text: String,
        range: NSRange,
        reveal: Bool,
        isProtected: (NSRange) -> Bool,
        apply: (NSRange) -> Void
    ) {
        pattern?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, !isProtected(match.range) else { return }
            let whole = match.range
            apply(match.range(at: contentGroup))
            styleMarker(storage, range: NSRange(location: whole.location, length: markerLength), reveal: reveal)
            styleMarker(storage, range: NSRange(location: NSMaxRange(whole) - markerLength, length: markerLength), reveal: reveal)
        }
    }

    // MARK: Helpers

    private func styleMarker(_ storage: NSTextStorage, range: NSRange, reveal: Bool) {
        if reveal {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        } else {
            collapse(storage, range: range)
        }
    }

    /// Hidden list markers use a small monospaced font so `[ ]`/`[x]` measure identically
    /// and stay narrower than their slot; `setWidth` then pads with positive kern only.
    private func hide(_ storage: NSTextStorage, range: NSRange) {
        storage.addAttributes([
            .foregroundColor: NSColor.clear,
            .font: NSFont.monospacedSystemFont(ofSize: 4, weight: .regular)
        ], range: range)
    }

    /// Makes characters invisible and ~zero-width while keeping them in the stored
    /// markdown. A near-zero font is used because TextKit clamps negative kerning.
    private func collapse(_ storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttributes([
            .foregroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.01)
        ], range: range)
    }

    private func setWidth(_ storage: NSTextStorage, range: NSRange, to width: CGFloat) {
        guard range.length > 0 else { return }
        let natural = storage.attributedSubstring(from: range).size().width
        storage.addAttribute(.kern, value: width - natural, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
    }

    private func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }

    private func paragraphStyle(
        firstIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0,
        spacingBefore: CGFloat = 0,
        spacing: CGFloat = 6
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = spacingBefore
        style.firstLineHeadIndent = firstIndent
        style.headIndent = headIndent
        style.tailIndent = tailIndent
        return style
    }
}

// MARK: - Layout Manager (block decorations)

final class NoteLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first, storage.length > 0 else { return }

        let visibleCharacters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(.noteBlock, in: visibleCharacters) { value, range, _ in
            guard let raw = value as? Int, let decoration = NoteBlockDecoration(rawValue: raw) else { return }
            var blockRange = range
            storage.attribute(.noteBlock, at: range.location, longestEffectiveRange: &blockRange, in: fullRange)
            draw(decoration, characterRange: blockRange, container: container, origin: origin)
        }

        storage.enumerateAttribute(.noteCheckbox, in: visibleCharacters) { value, range, _ in
            guard let isChecked = value as? Bool else { return }
            drawCheckbox(isChecked: isChecked, characterRange: range, origin: origin)
        }
    }

    private func draw(_ decoration: NoteBlockDecoration, characterRange: NSRange, container: NSTextContainer, origin: NSPoint) {
        let glyphs = glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let firstLine = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let lastLine = lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
        let padding = container.lineFragmentPadding

        switch decoration {
        case .bullet:
            guard let anchor = markerAnchor(for: characterRange) else { return }
            let diameter = max(4, round(anchor.font.pointSize * 0.36))
            let rect = NSRect(
                x: origin.x + anchor.x + 5,
                y: origin.y + anchor.baseline - anchor.font.xHeight / 2 - diameter / 2,
                width: diameter,
                height: diameter
            )
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: rect).fill()

        case .quote:
            let indent = (textStorage?.attribute(.paragraphStyle, at: characterRange.location, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
            let rect = NSRect(
                x: origin.x + firstLine.minX + padding + max(0, indent - 12),
                y: origin.y + firstLine.minY,
                width: 3,
                height: lastLine.maxY - firstLine.minY - 2
            )
            NSColor.controlAccentColor.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()

        case .divider:
            guard let anchor = markerAnchor(for: characterRange) else { return }
            let y = origin.y + anchor.baseline - anchor.font.xHeight / 2
            let rect = NSRect(x: origin.x + firstLine.minX + padding, y: y, width: container.size.width - padding * 2, height: 1)
            NSColor.separatorColor.setFill()
            rect.fill()

        case .codeBlock:
            let rect = NSRect(
                x: origin.x + firstLine.minX + padding,
                y: origin.y + firstLine.minY,
                width: container.size.width - padding * 2,
                height: lastLine.maxY - firstLine.minY
            )
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
    }

    private func drawCheckbox(isChecked: Bool, characterRange: NSRange, origin: NSPoint) {
        guard let anchor = markerAnchor(for: characterRange) else { return }
        let color = isChecked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        // Palette layers for checkmark.square.fill are [checkmark, square].
        let palette: [NSColor] = isChecked ? [.white, color] : [color]
        let configuration = NSImage.SymbolConfiguration(pointSize: anchor.font.pointSize + 1, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: palette))
        guard let image = NSImage(systemSymbolName: isChecked ? "checkmark.square.fill" : "square", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let centerY = origin.y + anchor.baseline - anchor.font.capHeight / 2
        let rect = NSRect(
            x: origin.x + anchor.x + 1,
            y: centerY - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// Left edge and baseline (container coordinates) of a marker's first glyph. The font
    /// comes from the text after the marker, since hidden markers use a shrunken font.
    private func markerAnchor(for characterRange: NSRange) -> (x: CGFloat, baseline: CGFloat, font: NSFont)? {
        guard let storage = textStorage, characterRange.location < storage.length else { return nil }
        let glyphIndex = glyphIndexForCharacter(at: characterRange.location)
        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let location = location(forGlyphAt: glyphIndex)
        let fontIndex = NSMaxRange(characterRange) < storage.length ? NSMaxRange(characterRange) : characterRange.location
        let font = storage.attribute(.font, at: fontIndex, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 14)
        return (lineRect.minX + location.x, lineRect.minY + location.y, font)
    }
}

// MARK: - Text View

final class NoteTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    /// Lets an open menu consume arrow/return/escape before normal editing.
    var commandInterceptor: ((Selector) -> Bool)?
    var onScroll: (() -> Void)?
    var onSelectionSettled: (() -> Void)?
    private(set) var isTrackingMouse = false
    private var scrollObserver: NSObjectProtocol?

    static func make() -> NoteTextView {
        let storage = NSTextStorage()
        let layoutManager = NoteLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NoteTextView(frame: .zero, textContainer: container)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        return textView
    }

    var placeholder = "Type '/' for commands, or just start writing…"

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font = typingAttributes[.font] as? NSFont else { return }
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: font,
            .foregroundColor: NSColor.placeholderTextColor
        ])
    }

    override func didChangeText() {
        super.didChangeText()
        // The placeholder only paints for an empty document, so redraw on the empty/non-empty edge.
        if (string as NSString).length <= 1 { needsDisplay = true }
    }

    func contentHeight(forWidth width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return 0 }
        let containerWidth = max(0, width - textContainerInset.width * 2)
        if textContainer.size.width != containerWidth {
            textContainer.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { onFocusChange?(true) }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { onFocusChange?(false) }
        return didResign
    }

    override func doCommand(by selector: Selector) {
        if commandInterceptor?(selector) == true { return }
        super.doCommand(by: selector)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onScroll?() }
        }
    }

    // MARK: Line Context

    struct LineContext {
        let range: NSRange
        let line: NoteLine
        let isInsideCodeFence: Bool

        var markerRange: NSRange {
            NSRange(location: range.location + line.indentLength, length: line.markerLength)
        }

        var contentRange: NSRange {
            let start = NSMaxRange(markerRange)
            return NSRange(location: start, length: NSMaxRange(range) - start)
        }

        var isListItem: Bool {
            switch line.kind {
            case .bullet, .numbered, .task: return true
            default: return false
            }
        }
    }

    func lineContext(at location: Int) -> LineContext {
        let text = string as NSString
        let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
        var lineEnd = NSMaxRange(paragraph)
        while lineEnd > paragraph.location, let scalar = UnicodeScalar(text.character(at: lineEnd - 1)),
              CharacterSet.newlines.contains(scalar) {
            lineEnd -= 1
        }
        let range = NSRange(location: paragraph.location, length: lineEnd - paragraph.location)

        var isInsideFence = false
        text.enumerateSubstrings(in: NSRange(location: 0, length: paragraph.location), options: .byParagraphs) { line, _, _, _ in
            if line?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
                isInsideFence.toggle()
            }
        }
        return LineContext(range: range, line: NoteLine.parse(text.substring(with: range)), isInsideCodeFence: isInsideFence)
    }

    /// Replaces text through the undo-aware path so every edit is undoable.
    func replace(_ range: NSRange, with replacement: String, selecting selection: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection ?? NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }

    private var caret: Int? {
        let selection = selectedRange()
        return selection.length == 0 ? selection.location : nil
    }

    // MARK: Block Keyboard Behavior

    override func insertNewline(_ sender: Any?) {
        guard let caret else { return super.insertNewline(sender) }
        let context = lineContext(at: caret)
        let text = string as NSString
        let lineText = text.substring(with: context.range)

        if context.isInsideCodeFence {
            let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })
            return replace(NSRange(location: caret, length: 0), with: "\n" + indent)
        }

        if lineText.trimmingCharacters(in: .whitespaces).hasPrefix("```"), caret == NSMaxRange(context.range),
           text.components(separatedBy: "```").count % 2 == 0 {
            replace(NSRange(location: caret, length: 0), with: "\n\n```")
            return setSelectedRange(NSRange(location: caret + 1, length: 0))
        }

        let isContinuable = context.isListItem || context.line.kind == .quote
        guard isContinuable, caret >= context.contentRange.location else { return super.insertNewline(sender) }

        if context.contentRange.length == 0 || text.substring(with: context.contentRange).trimmingCharacters(in: .whitespaces).isEmpty {
            if context.line.indentLevel > 0 {
                return outdent(context)
            }
            return replace(NSRange(location: context.range.location, length: NSMaxRange(context.markerRange) - context.range.location), with: "")
        }

        let indent = text.substring(with: NSRange(location: context.range.location, length: context.line.indentLength))
        replace(NSRange(location: caret, length: 0), with: "\n" + indent + nextMarker(for: context))
    }

    private func nextMarker(for context: LineContext) -> String {
        let marker = (string as NSString).substring(with: context.markerRange)
        switch context.line.kind {
        case .task:
            return String(marker.prefix(1)) + " [ ] "
        case .numbered(let number):
            let punctuation = marker.contains(")") ? ")" : "."
            return "\(number + 1)\(punctuation) "
        default:
            return marker
        }
    }

    override func insertTab(_ sender: Any?) {
        guard let caret else { return super.insertTab(sender) }
        let context = lineContext(at: caret)
        guard context.isListItem, !context.isInsideCodeFence else { return super.insertTab(sender) }
        replace(NSRange(location: context.range.location, length: 0), with: "  ", selecting: NSRange(location: caret + 2, length: 0))
    }

    override func insertBacktab(_ sender: Any?) {
        guard let caret else { return super.insertBacktab(sender) }
        let context = lineContext(at: caret)
        guard context.line.indentLength > 0, !context.isInsideCodeFence else { return super.insertBacktab(sender) }
        outdent(context)
    }

    private func outdent(_ context: LineContext) {
        let text = string as NSString
        let leading = text.substring(with: NSRange(location: context.range.location, length: context.line.indentLength))
        let removeLength = leading.hasPrefix("\t") ? 1 : min(2, leading.prefix { $0 == " " }.count)
        guard removeLength > 0 else { return }
        let caretLocation = selectedRange().location
        replace(
            NSRange(location: context.range.location, length: removeLength),
            with: "",
            selecting: NSRange(location: max(context.range.location, caretLocation - removeLength), length: 0)
        )
    }

    override func deleteBackward(_ sender: Any?) {
        guard let caret else { return super.deleteBackward(sender) }
        let context = lineContext(at: caret)
        guard !context.isInsideCodeFence, caret == context.contentRange.location, caret > context.range.location else {
            return super.deleteBackward(sender)
        }
        if context.line.markerLength > 0 {
            return replace(context.markerRange, with: "")
        }
        outdent(context)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if (insertString as? String) == " ", let caret {
            let context = lineContext(at: caret)
            let prefixRange = NSRange(location: context.range.location, length: caret - context.range.location)
            let typedPrefix = (string as NSString).substring(with: prefixRange)
            if !context.isInsideCodeFence, context.line.kind == .paragraph, typedPrefix == "[]" || typedPrefix == "[ ]" {
                return replace(prefixRange, with: "- [ ] ")
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    // MARK: Slash Commands & Block Conversion

    /// Range of a `/query` being typed at the caret, when it starts a word.
    func slashCommandRange() -> NSRange? {
        guard let caret else { return nil }
        let context = lineContext(at: caret)
        guard !context.isInsideCodeFence, caret > context.range.location else { return nil }
        let text = string as NSString
        let typed = text.substring(with: NSRange(location: context.range.location, length: caret - context.range.location)) as NSString
        let slash = typed.range(of: "/", options: .backwards)
        guard slash.location != NSNotFound else { return nil }

        let query = typed.substring(from: slash.location + 1)
        guard query.count <= 24, query.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        if slash.location > 0 {
            let previous = typed.substring(with: NSRange(location: slash.location - 1, length: 1))
            guard previous == " " || previous == "\t" else { return nil }
        }
        return NSRange(location: context.range.location + slash.location, length: caret - context.range.location - slash.location)
    }

    /// Converts the caret's line into `type`, optionally deleting a typed `/command` first.
    func applyBlock(_ type: NoteBlockType, removing commandRange: NSRange? = nil) {
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        if var commandRange {
            let commandContext = lineContext(at: commandRange.location)
            let previous = NSRange(location: commandRange.location - 1, length: 1)
            if previous.location >= commandContext.contentRange.location,
               (string as NSString).substring(with: previous) == " " {
                commandRange = NSUnionRange(previous, commandRange)
            }
            replace(commandRange, with: "")
        }
        let selection = selectedRange()
        let context = lineContext(at: selection.location)
        let text = string as NSString
        let content = text.substring(with: context.contentRange)
        let selectedLines = selectedLineStarts()

        switch type {
        case .divider:
            let lineText = text.substring(with: context.range)
            replace(context.range, with: content.isEmpty ? "---\n" : lineText + "\n---\n")

        case .codeBlock:
            let lastContext = lineContext(at: selectedLines.last ?? context.range.location)
            let blockRange = NSRange(location: context.range.location, length: NSMaxRange(lastContext.range) - context.range.location)
            let body = selectedLines.count > 1 ? text.substring(with: blockRange) : content
            replace(
                blockRange,
                with: "```\n" + body + "\n```",
                selecting: NSRange(location: blockRange.location + 4 + (body as NSString).length, length: 0)
            )

        default:
            guard selection.length > 0 else {
                let prefixRange = NSRange(location: context.range.location, length: context.line.indentLength + context.line.markerLength)
                let newPrefix = prefix(for: type, context: context, number: 1)
                let caretOffset = max(0, selection.location - NSMaxRange(prefixRange))
                return replace(prefixRange, with: newPrefix, selecting: NSRange(location: prefixRange.location + (newPrefix as NSString).length + caretOffset, length: 0))
            }

            let firstStart = selectedLines.first ?? selection.location
            let originalEnd = NSMaxRange(lineContext(at: selectedLines.last ?? firstStart).range)
            // Walk bottom-up so earlier line offsets stay valid while prefixes change length.
            var delta = 0
            for (index, start) in selectedLines.enumerated().reversed() {
                let lineContext = lineContext(at: start)
                let prefixRange = NSRange(location: start, length: lineContext.line.indentLength + lineContext.line.markerLength)
                let newPrefix = prefix(for: type, context: lineContext, number: index + 1)
                delta += (newPrefix as NSString).length - prefixRange.length
                replace(prefixRange, with: newPrefix)
            }
            setSelectedRange(NSRange(location: firstStart, length: originalEnd + delta - firstStart))
        }
    }

    func currentBlockType() -> NoteBlockType? {
        let context = lineContext(at: selectedRange().location)
        guard !context.isInsideCodeFence else { return .codeBlock }
        switch context.line.kind {
        case .paragraph: return .text
        case .heading(let level): return [.heading1, .heading2, .heading3][level - 1]
        case .bullet: return .bulletList
        case .numbered: return .numberedList
        case .task: return .todo
        case .quote: return .quote
        case .divider: return .divider
        }
    }

    private func prefix(for type: NoteBlockType, context: LineContext, number: Int) -> String {
        let indent = type.isListType ? (string as NSString).substring(with: NSRange(location: context.range.location, length: context.line.indentLength)) : ""
        return indent + (type == .numberedList ? "\(number). " : type.linePrefix)
    }

    private func selectedLineStarts() -> [Int] {
        let text = string as NSString
        let selection = selectedRange()
        guard selection.length > 0 else {
            return [text.paragraphRange(for: selection).location]
        }
        // Exclude the line after a selection that ends right on a newline.
        let endsOnNewline = text.substring(with: NSRange(location: NSMaxRange(selection) - 1, length: 1)) == "\n"
        let trimmed = NSRange(location: selection.location, length: selection.length - (endsOnNewline ? 1 : 0))
        var starts: [Int] = []
        text.enumerateSubstrings(in: text.paragraphRange(for: trimmed), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            starts.append(range.location)
        }
        return starts
    }

    // MARK: Inline Formatting

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, key) {
        case ([.command], "b"): toggleInline("**")
        case ([.command], "i"): toggleInline("*")
        case ([.command], "e"): toggleInline("`")
        case ([.command, .shift], "x"): toggleInline("~~")
        case ([.command], "k"): insertLink()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Whether the selection sits directly inside `marker` delimiters.
    func isWrapped(in marker: String) -> Bool {
        let text = string as NSString
        let selection = selectedRange()

        // `*` and `**` share a character, so count the star run on each side instead.
        if marker == "*" || marker == "**" {
            func starRun(from start: Int, step: Int) -> Int {
                var count = 0
                var index = start
                while index >= 0, index < text.length, text.character(at: index) == 0x2A {
                    count += 1
                    index += step
                }
                return count
            }
            let stars = min(starRun(from: selection.location - 1, step: -1), starRun(from: NSMaxRange(selection), step: 1))
            return marker == "*" ? (stars == 1 || stars >= 3) : stars >= 2
        }

        let markerLength = (marker as NSString).length
        let before = NSRange(location: selection.location - markerLength, length: markerLength)
        let after = NSRange(location: NSMaxRange(selection), length: markerLength)
        return before.location >= 0 && NSMaxRange(after) <= text.length
            && text.substring(with: before) == marker && text.substring(with: after) == marker
    }

    /// Wraps the selection in `marker`, or unwraps it when it is already wrapped.
    func toggleInline(_ marker: String) {
        let text = string as NSString
        let selection = selectedRange()
        let markerLength = (marker as NSString).length

        if isWrapped(in: marker) {
            let before = NSRange(location: selection.location - markerLength, length: markerLength)
            let after = NSRange(location: NSMaxRange(selection), length: markerLength)
            let outer = NSRange(location: before.location, length: NSMaxRange(after) - before.location)
            return replace(outer, with: text.substring(with: selection), selecting: NSRange(location: before.location, length: selection.length))
        }

        let selected = text.substring(with: selection)
        let isOtherStarMarker = marker == "*" && selected.hasPrefix("**") && !selected.hasPrefix("***")
        if selection.length > markerLength * 2, selected.hasPrefix(marker), selected.hasSuffix(marker), !isOtherStarMarker {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            return replace(selection, with: inner, selecting: NSRange(location: selection.location, length: (inner as NSString).length))
        }

        replace(
            selection,
            with: marker + selected + marker,
            selecting: NSRange(location: selection.location + markerLength, length: selection.length)
        )
    }

    func insertLink() {
        let selection = selectedRange()
        let label = (string as NSString).substring(with: selection)
        let placeholderURL = "https://"
        let replacement = "[\(label)](\(placeholderURL))"
        let selectionAfter = label.isEmpty
            ? NSRange(location: selection.location + 1, length: 0)
            : NSRange(location: selection.location + (label as NSString).length + 3, length: (placeholderURL as NSString).length)
        replace(selection, with: replacement, selecting: selectionAfter)
    }

    // MARK: Checkboxes

    override func mouseDown(with event: NSEvent) {
        if let range = checkboxRange(at: convert(event.locationInWindow, from: nil)) {
            toggleCheckbox(markerRange: range)
            return
        }
        // super runs AppKit's drag-selection loop and returns on mouse-up.
        isTrackingMouse = true
        super.mouseDown(with: event)
        isTrackingMouse = false
        onSelectionSettled?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if checkboxRange(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.pointingHand.set()
        }
    }

    private func checkboxRange(at point: NSPoint) -> NSRange? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < storage.length else { return nil }

        var markerRange = NSRange()
        guard storage.attribute(.noteCheckbox, at: characterIndex, longestEffectiveRange: &markerRange, in: NSRange(location: 0, length: storage.length)) != nil else { return nil }

        let markerGlyphs = layoutManager.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: markerGlyphs, in: textContainer)
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: markerGlyphs.location, effectiveRange: nil)
        let hitRect = NSRect(x: rect.minX, y: lineRect.minY, width: 22, height: lineRect.height)
        return hitRect.contains(containerPoint) ? markerRange : nil
    }

    /// Flips the `[ ]`/`[x]` state character inside a `- [ ] ` marker.
    private func toggleCheckbox(markerRange: NSRange) {
        let stateRange = NSRange(location: markerRange.location + 3, length: 1)
        let current = (string as NSString).substring(with: stateRange)
        let replacement = current == " " ? "x" : " "
        guard shouldChangeText(in: stateRange, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: stateRange, with: replacement)
        didChangeText()
    }
}

// MARK: - Proxy

/// Lets SwiftUI toolbars drive the live text view (selection-aware formatting).
@MainActor
final class RichNoteEditorProxy {
    fileprivate weak var textView: NoteTextView?

    func applyBlock(_ type: NoteBlockType) {
        focusedTextView()?.applyBlock(type)
    }

    func apply(_ format: NoteInlineFormat) {
        guard let textView = focusedTextView() else { return }
        if format == .link {
            textView.insertLink()
        } else {
            textView.toggleInline(format.marker)
        }
    }

    private func focusedTextView() -> NoteTextView? {
        guard let textView else { return nil }
        if textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
        return textView
    }
}

// MARK: - SwiftUI Wrapper

/// Notion/TipTap-style live markdown editor. The bound text remains plain
/// markdown, so storage, Drive sync and card previews are unchanged.
struct RichNoteEditor: NSViewRepresentable {
    @Binding var text: String
    var usesMonospacedFont = false
    var minHeight: CGFloat = 160
    var proxy: RichNoteEditorProxy?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NoteTextView {
        let textView = NoteTextView.make()
        let coordinator = context.coordinator
        coordinator.textView = textView
        proxy?.textView = textView
        coordinator.styler.usesMonospacedFont = usesMonospacedFont
        textView.delegate = coordinator
        textView.textStorage?.delegate = coordinator
        textView.typingAttributes = coordinator.styler.baseAttributes
        textView.onFocusChange = { [weak coordinator] _ in
            coordinator?.restyle()
            coordinator?.updateMenus()
        }
        textView.commandInterceptor = { [weak coordinator] selector in
            coordinator?.handleCommand(selector) ?? false
        }
        textView.onScroll = { [weak coordinator] in
            coordinator?.updateMenus()
        }
        textView.onSelectionSettled = { [weak coordinator] in
            coordinator?.updateMenus()
        }
        textView.string = text
        coordinator.restyle()
        return textView
    }

    func updateNSView(_ textView: NoteTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        proxy?.textView = textView
        var needsRestyle = false
        if coordinator.styler.usesMonospacedFont != usesMonospacedFont {
            coordinator.styler.usesMonospacedFont = usesMonospacedFont
            needsRestyle = true
        }
        if textView.string != text {
            textView.string = text
            // Undo steps recorded against the previous note's text would corrupt this one.
            textView.undoManager?.removeAllActions()
            needsRestyle = true
        }
        if needsRestyle {
            coordinator.restyle()
            textView.invalidateIntrinsicContentSize()
        }
    }

    static func dismantleNSView(_ textView: NoteTextView, coordinator: Coordinator) {
        coordinator.dismissMenus()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NoteTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: max(minHeight, nsView.contentHeight(forWidth: width)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNoteEditor
        weak var textView: NoteTextView?
        let styler = NoteMarkdownStyler()
        private var activeRange: NSRange?

        init(parent: RichNoteEditor) {
            self.parent = parent
        }

        /// Paragraph range markers should be revealed in, or nil when unfocused.
        private func currentActiveRange() -> NSRange? {
            guard let textView, textView.window?.firstResponder === textView else { return nil }
            return (textView.string as NSString).paragraphRange(for: textView.selectedRange())
        }

        func restyle() {
            guard let storage = textView?.textStorage else { return }
            activeRange = currentActiveRange()
            storage.beginEditing()
            styler.style(storage, revealing: activeRange)
            storage.endEditing()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            textView.invalidateIntrinsicContentSize()
            updateMenus()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateMenus()
            guard currentActiveRange() != activeRange else { return }
            restyle()
        }

        // MARK: Menus

        private let slashPanel = NoteFloatingPanel()
        private var slashRange: NSRange?
        private var slashItems: [NoteBlockType] = []
        private var slashSelection = 0
        /// Escape closes the menu for this particular `/` until it is deleted.
        private var dismissedSlashLocation: Int?

        private let bubblePanel = NoteFloatingPanel()

        func updateMenus() {
            updateSlashMenu()
            updateBubbleMenu()
        }

        func dismissMenus() {
            hideSlashMenu(resetDismissal: true)
            bubblePanel.dismiss()
        }

        private func updateBubbleMenu() {
            guard let textView, let window = textView.window, window.firstResponder === textView,
                  !textView.isTrackingMouse, slashRange == nil else {
                return bubblePanel.dismiss()
            }
            let selection = textView.selectedRange()
            guard selection.length > 0, !textView.lineContext(at: selection.location).isInsideCodeFence else {
                return bubblePanel.dismiss()
            }

            let activeFormats = Set(NoteInlineFormat.allCases.filter { $0 != .link && textView.isWrapped(in: $0.marker) })
            let menu = FormattingBubbleMenu(
                activeFormats: activeFormats,
                activeBlock: textView.currentBlockType(),
                onFormat: { [weak self] format in self?.applyFormat(format) },
                onBlock: { [weak self] type in self?.textView?.applyBlock(type) }
            )
            let anchor = textView.firstRect(forCharacterRange: selection, actualRange: nil)
            bubblePanel.present(AnyView(menu), anchor: anchor, parentWindow: window, preferAbove: true)
        }

        private func applyFormat(_ format: NoteInlineFormat) {
            guard let textView else { return }
            if format == .link {
                textView.insertLink()
            } else {
                textView.toggleInline(format.marker)
            }
        }

        private func updateSlashMenu() {
            guard let textView, textView.window?.firstResponder === textView,
                  let range = textView.slashCommandRange() else {
                return hideSlashMenu(resetDismissal: true)
            }
            guard range.location != dismissedSlashLocation else {
                return hideSlashMenu(resetDismissal: false)
            }

            let query = String((textView.string as NSString).substring(with: range).dropFirst())
            let items = NoteBlockType.matching(query)
            guard !items.isEmpty else {
                return hideSlashMenu(resetDismissal: false)
            }
            if range.location != slashRange?.location || items != slashItems {
                slashSelection = 0
            }
            slashRange = range
            slashItems = items
            presentSlashMenu()
        }

        private func presentSlashMenu() {
            guard let textView, let window = textView.window, let slashRange else { return }
            let anchor = textView.firstRect(forCharacterRange: slashRange, actualRange: nil)
            let menu = SlashCommandMenu(items: slashItems, selectedIndex: slashSelection) { [weak self] type in
                self?.applySlashCommand(type)
            }
            slashPanel.present(AnyView(menu), anchor: anchor, parentWindow: window)
        }

        private func hideSlashMenu(resetDismissal: Bool) {
            slashPanel.dismiss()
            slashRange = nil
            if resetDismissal {
                dismissedSlashLocation = nil
            }
        }

        private func applySlashCommand(_ type: NoteBlockType) {
            guard let textView, let slashRange else { return }
            hideSlashMenu(resetDismissal: true)
            textView.applyBlock(type, removing: slashRange)
        }

        func handleCommand(_ selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)), bubblePanel.isVisible {
                bubblePanel.dismiss()
                return true
            }
            guard let slashRange, !slashItems.isEmpty else { return false }
            let count = slashItems.count
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                slashSelection = (slashSelection - 1 + count) % count
                presentSlashMenu()
            case #selector(NSResponder.moveDown(_:)):
                slashSelection = (slashSelection + 1) % count
                presentSlashMenu()
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                applySlashCommand(slashItems[slashSelection])
            case #selector(NSResponder.cancelOperation(_:)):
                dismissedSlashLocation = slashRange.location
                hideSlashMenu(resetDismissal: false)
            default:
                return false
            }
            return true
        }
    }
}

extension RichNoteEditor.Coordinator: NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // Selection hasn't moved yet here, so the edited paragraph stands in for the caret's.
        let active = (textStorage.string as NSString).paragraphRange(for: editedRange)
        activeRange = active
        styler.style(textStorage, revealing: active)
    }
}
