//
//  View+Tooltip.swift
//  SyncBoard
//

import SwiftUI
import AppKit

private struct NativeTooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    /// Attaches an AppKit-level tooltip that works reliably inside NSPopover and floating windows.
    func nativeTooltip(_ text: String) -> some View {
        self
            .background(NativeTooltipView(text: text))
            .help(text)
    }
}
