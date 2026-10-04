//
//  View+Scrollbar.swift
//  SyncBoard
//

import SwiftUI
import AppKit

private struct ScrollControlSizeModifier: NSViewRepresentable {
    var size: NSControl.ControlSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyScrollerSize(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyScrollerSize(from: nsView)
        }
    }

    private func applyScrollerSize(from view: NSView) {
        guard let scrollView = findEnclosingScrollView(from: view) else { return }
        var needsTile = false
        if let vertical = scrollView.verticalScroller, vertical.controlSize != size {
            vertical.controlSize = size
            needsTile = true
        }
        if let horizontal = scrollView.horizontalScroller, horizontal.controlSize != size {
            horizontal.controlSize = size
            needsTile = true
        }
        if needsTile {
            scrollView.tile()
        }
    }

    private func findEnclosingScrollView(from view: NSView) -> NSScrollView? {
        if let direct = view.enclosingScrollView {
            return direct
        }
        var current: NSView? = view.superview
        while let v = current {
            if let sv = v as? NSScrollView {
                return sv
            }
            if let direct = v.enclosingScrollView {
                return direct
            }
            current = v.superview
        }
        if let sv = findScrollViewInSubviews(view) {
            return sv
        }
        return nil
    }

    private func findScrollViewInSubviews(_ view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView {
            return sv
        }
        for sub in view.subviews {
            if let found = findScrollViewInSubviews(sub) {
                return found
            }
        }
        return nil
    }
}

extension View {
    /// Configures the enclosing scroll view's scroller size to be narrow (e.g. `.mini` or `.small`).
    func scrollControlSize(_ size: NSControl.ControlSize = .mini) -> some View {
        background(ScrollControlSizeModifier(size: size))
    }
}
