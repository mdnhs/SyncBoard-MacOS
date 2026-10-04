//
//  SensitiveTextReveal.swift
//  SyncBoard
//

import SwiftUI

/// Wraps sensitive clipboard text so it renders masked by default. Tapping
/// it reveals the real text for 2 seconds before auto-hiding again; tapping
/// again while revealed hides it immediately instead of waiting out the timer.
///
/// `content` receives whichever string (masked or real) should currently be
/// rendered, so callers keep full control over font/color/lineLimit at the
/// call site instead of this view dictating a fixed style.
struct SensitiveTextReveal<Content: View>: View {
    let text: String
    let isSensitive: Bool
    @ViewBuilder let content: (String) -> Content

    @State private var isRevealed = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        if isSensitive {
            content(isRevealed ? text : SensitiveContentDetector.mask(text))
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleReveal)
        } else {
            content(text)
        }
    }

    private func toggleReveal() {
        hideTask?.cancel()
        if isRevealed {
            isRevealed = false
            return
        }
        isRevealed = true
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            isRevealed = false
        }
    }
}
