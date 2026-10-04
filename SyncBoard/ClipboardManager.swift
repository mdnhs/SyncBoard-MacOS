//
//  ClipboardManager.swift
//  SyncBoard
//

import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ClipboardManager {
    static let shared = ClipboardManager()

    private(set) var history: [ClipboardItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var maxHistoryCount: Int { AppSettings.shared.maxHistoryCount }
    private let storageKey = "com.nazmulhsourab.SyncBoard.clipboardHistory"

    private init() {
        lastChangeCount = pasteboard.changeCount
        loadHistory()
        purgeExpiredHistory()
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
        copyRawText(item.text, isSensitive: item.isSensitive)
    }

    /// Writes arbitrary text without going through a `ClipboardItem`.
    func copyRawText(_ text: String, isSensitive: Bool? = nil) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        let sensitive = isSensitive ?? SensitiveContentDetector.looksSensitive(text)
        CopyToast.show(for: text, isSensitive: sensitive)
    }

    func togglePin(for item: ClipboardItem) {
        guard let index = history.firstIndex(where: { $0.id == item.id }) else { return }
        history[index].isPinned.toggle()
        saveHistory()
        GoogleDriveSyncManager.shared.scheduleSync()
    }

    func delete(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        saveHistory()
        GoogleDriveSyncManager.shared.scheduleSync()
    }

    func clearAll(preservePinned: Bool = true) {
        if preservePinned {
            history.removeAll(where: { !$0.isPinned })
        } else {
            history.removeAll()
        }
        saveHistory()
        GoogleDriveSyncManager.shared.scheduleSync()
    }

    func trimHistoryIfNeeded() {
        let unpinned = history.filter { !$0.isPinned }
        let pinned = history.filter { $0.isPinned }

        if unpinned.count > maxHistoryCount {
            let trimmedUnpinned = Array(unpinned.prefix(maxHistoryCount))
            history = (pinned + trimmedUnpinned).sorted(by: { $0.date > $1.date })
            saveHistory()
        }
    }

    func purgeExpiredHistory() {
        let retentionDays = AppSettings.shared.historyRetentionDays
        guard retentionDays > 0 else { return }
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }

        let originalCount = history.count
        // Pinned items are protected from automatic age purging
        history.removeAll { !$0.isPinned && $0.date < cutoffDate }
        if history.count != originalCount {
            saveHistory()
        }
    }

    /// Replaces local history with the result of a Google Drive merge.
    func replaceHistory(with items: [ClipboardItem]) {
        var merged = items.sorted { $0.date > $1.date }
        let unpinned = merged.filter { !$0.isPinned }
        let pinned = merged.filter { $0.isPinned }

        if unpinned.count > maxHistoryCount {
            let trimmedUnpinned = Array(unpinned.prefix(maxHistoryCount))
            merged = (pinned + trimmedUnpinned).sorted(by: { $0.date > $1.date })
        }
        history = merged
        saveHistory()
    }

    // MARK: - Export & Import
    func exportToJSON() -> URL? {
        guard let data = try? JSONEncoder().encode(history) else { return nil }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("SyncBoard_Backup_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json")
        try? data.write(to: fileURL)
        return fileURL
    }

    func exportToCSV() -> URL? {
        var csvString = "ID,Date,Kind,IsPinned,IsSensitive,Content\n"
        for item in history {
            let cleanText = item.text.replacingOccurrences(of: "\"", with: "\"\"")
            let dateStr = item.date.ISO8601Format()
            csvString += "\"\(item.id)\",\"\(dateStr)\",\"\(item.contentKind.rawValue)\",\"\(item.isPinned)\",\"\(item.isSensitive)\",\"\(cleanText)\"\n"
        }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("SyncBoard_Export_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).csv")
        try? csvString.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func importFromJSON(url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return 0
        }

        var newCount = 0
        for item in imported {
            if !history.contains(where: { $0.id == item.id || $0.text == item.text }) {
                history.append(item)
                newCount += 1
            }
        }
        history.sort(by: { $0.date > $1.date })
        saveHistory()
        GoogleDriveSyncManager.shared.scheduleSync()
        return newCount
    }

    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard history.first?.text != text else { return }

        // 1. Check if frontmost application is blacklisted/excluded
        var frontmostBundleId: String?
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            frontmostBundleId = frontmostApp.bundleIdentifier
            if let bundleId = frontmostBundleId, AppSettings.shared.excludedAppBundleIdentifiers.contains(bundleId) {
                return
            }
        }

        // 2. Check if the copied text itself contains a blacklisted domain/URL
        if AppSettings.shared.isDomainOrURLBlocked(text) {
            return
        }

        // 3. Check if the pasteboard metadata contains a blacklisted source URL (HTML / URL types)
        if isPasteboardSourceBlocked() {
            return
        }

        // 4. If frontmost app is a browser, check if active tab URL is blacklisted
        if let bundleId = frontmostBundleId, isFrontmostBrowserBlocked(bundleId: bundleId) {
            return
        }

        // Password managers mark a copied secret with this pseudo-type
        let isConcealed = pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) ?? false

        if isConcealed && AppSettings.shared.ignorePasswordManagerCopies {
            return
        }

        let isSensitiveItem = isConcealed ? true : (AppSettings.shared.maskSensitiveContent ? nil : false)
        history.insert(ClipboardItem(text: text, isSensitive: isSensitiveItem), at: 0)
        trimHistoryIfNeeded()
        saveHistory()
        GoogleDriveSyncManager.shared.scheduleSync()
    }

    // MARK: - Website Exclusion Helpers
    private func isPasteboardSourceBlocked() -> Bool {
        guard !AppSettings.shared.excludedWebDomains.isEmpty else { return false }

        // Check public.url / Apple URL pasteboard types
        let urlTypeNames = [
            "public.url",
            "Apple URL pasteboard type",
            "public.url-name",
            "WebURLsWithTitlesPboardType"
        ]
        for typeName in urlTypeNames {
            if let urlString = pasteboard.string(forType: NSPasteboard.PasteboardType(typeName)),
               !urlString.isEmpty {
                if AppSettings.shared.isDomainOrURLBlocked(urlString) {
                    return true
                }
            }
        }

        // Check HTML source metadata (Chrome, Safari, Arc, Brave put source URLs in HTML clipboard)
        let htmlTypeNames = [
            "public.html",
            "text/html",
            "Apple HTML pasteboard type"
        ]
        for typeName in htmlTypeNames {
            if let html = pasteboard.string(forType: NSPasteboard.PasteboardType(typeName)),
               !html.isEmpty {
                if let sourceURL = extractSourceURL(from: html), AppSettings.shared.isDomainOrURLBlocked(sourceURL) {
                    return true
                }
            }
        }

        return false
    }

    private func extractSourceURL(from html: String) -> String? {
        // Chromium headers: SourceURL:https://...
        if let range = html.range(of: "SourceURL:", options: .caseInsensitive) {
            let remainder = html[range.upperBound...]
            let line = remainder.prefix(while: { $0 != "\r" && $0 != "\n" && $0 != "\"" && $0 != "<" })
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        // HTML meta: <meta name="source-url" content="https://...">
        if let metaRange = html.range(of: "source-url", options: .caseInsensitive) {
            let remainder = html[metaRange.upperBound...]
            if let contentRange = remainder.range(of: "content=\"", options: .caseInsensitive) {
                let urlRemainder = remainder[contentRange.upperBound...]
                let urlStr = urlRemainder.prefix(while: { $0 != "\"" })
                let trimmed = String(urlStr).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func isFrontmostBrowserBlocked(bundleId: String) -> Bool {
        guard !AppSettings.shared.excludedWebDomains.isEmpty else { return false }
        guard let urlString = getBrowserActiveTabURL(bundleId: bundleId), !urlString.isEmpty else {
            return false
        }
        return AppSettings.shared.isDomainOrURLBlocked(urlString)
    }

    private func getBrowserActiveTabURL(bundleId: String) -> String? {
        let chromiumBundles: Set<String> = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.google.Chrome.dev",
            "com.google.Chrome.beta",
            "com.brave.Browser",
            "com.brave.Browser.nightly",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.Canary",
            "company.thebrowser.Browser", // Arc
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
            "org.chromium.Chromium"
        ]

        let safariBundles: Set<String> = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.kagi.kagisafari" // Orion
        ]

        if chromiumBundles.contains(bundleId) {
            let script = "tell application id \"\(bundleId)\" to return URL of active tab of front window"
            return runAppleScript(script)
        } else if safariBundles.contains(bundleId) {
            let script = "tell application id \"\(bundleId)\" to return URL of front document"
            return runAppleScript(script)
        }

        return nil
    }

    private func runAppleScript(_ scriptSource: String) -> String? {
        guard let appleScript = NSAppleScript(source: scriptSource) else { return nil }
        var errorInfo: NSDictionary?
        let output = appleScript.executeAndReturnError(&errorInfo)
        if errorInfo == nil, let val = output.stringValue, !val.isEmpty {
            return val
        }
        return nil
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
