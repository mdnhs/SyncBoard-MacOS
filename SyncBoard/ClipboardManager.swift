//
//  ClipboardManager.swift
//  SyncBoard
//

import AppKit
import Observation

@MainActor
@Observable
final class ClipboardManager {
    static let shared = ClipboardManager()

    private(set) var history: [ClipboardItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let maxHistoryCount = 50
    private let storageKey = "com.nazmulhsourab.SyncBoard.clipboardHistory"

    private init() {
        lastChangeCount = pasteboard.changeCount
        loadHistory()
    }

    func startMonitoring() {
        // Polling is the only reliable way to observe NSPasteboard.general changes
        // from other apps; there is no system notification for pasteboard writes.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        copyRawText(item.text)
    }

    /// Writes arbitrary text (e.g. just the code portion of a mixed
    /// prose+code item) without going through a `ClipboardItem`.
    func copyRawText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func delete(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        saveHistory()
    }

    func clearAll() {
        history.removeAll()
        saveHistory()
    }

    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard history.first?.text != text else { return }

        history.insert(ClipboardItem(text: text), at: 0)
        if history.count > maxHistoryCount {
            history.removeLast(history.count - maxHistoryCount)
        }
        saveHistory()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        history = decoded
    }
}
