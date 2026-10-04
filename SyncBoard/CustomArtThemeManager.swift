//
//  CustomArtThemeManager.swift
//  SyncBoard
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Represents a user-uploaded custom SVG art theme with mandatory Light and Dark variants.
struct CustomArtTheme: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var lightSvgData: String // base64 encoded SVG data
    var darkSvgData: String  // base64 encoded SVG data
    var lightSvgByteCount: Int64
    var darkSvgByteCount: Int64
    var createdAt: Date

    var totalSizeBytes: Int64 {
        lightSvgByteCount + darkSvgByteCount
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}

/// Manages custom SVG art theme storage, persistence, caching, and total device disk usage.
@Observable
final class CustomArtThemeManager {
    static let shared = CustomArtThemeManager()

    var customThemes: [CustomArtTheme] = []
    private var imageCache: [String: NSImage] = [:]

    private let storageFileName = "custom_art_themes.json"

    private init() {
        loadThemes()
    }

    /// Total storage on device used by custom uploaded SVG art themes.
    var totalStorageUsedBytes: Int64 {
        customThemes.reduce(0) { $0 + $1.totalSizeBytes }
    }

    /// Formatted storage string (e.g. "48 KB" or "1.2 MB").
    var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorageUsedBytes, countStyle: .file)
    }

    // MARK: - Add / Delete
    func addTheme(name: String, lightSvgData: Data, darkSvgData: Data) throws -> CustomArtTheme {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw NSError(domain: "SyncBoard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Theme name cannot be empty."])
        }

        // Validate both are valid SVGs that can be rendered
        guard let _ = NSImage(data: lightSvgData) else {
            throw NSError(domain: "SyncBoard", code: 2, userInfo: [NSLocalizedDescriptionKey: "Light variant is not a valid SVG file."])
        }
        guard let _ = NSImage(data: darkSvgData) else {
            throw NSError(domain: "SyncBoard", code: 3, userInfo: [NSLocalizedDescriptionKey: "Dark variant is not a valid SVG file."])
        }

        let id = ULID.generate()
        let lightB64 = lightSvgData.base64EncodedString()
        let darkB64 = darkSvgData.base64EncodedString()

        let theme = CustomArtTheme(
            id: id,
            name: cleanName,
            lightSvgData: lightB64,
            darkSvgData: darkB64,
            lightSvgByteCount: Int64(lightSvgData.count),
            darkSvgByteCount: Int64(darkSvgData.count),
            createdAt: Date()
        )

        customThemes.append(theme)
        saveThemes()
        return theme
    }

    func deleteTheme(id: String) {
        customThemes.removeAll { $0.id == id }
        let keysToRemove = imageCache.keys.filter { $0.hasPrefix(id) }
        for key in keysToRemove {
            imageCache.removeValue(forKey: key)
        }
        saveThemes()
    }

    // MARK: - Image & View Helpers
    func nsImage(for id: String, isDark: Bool) -> NSImage? {
        guard let theme = customThemes.first(where: { $0.id == id }) else { return nil }
        let key = "\(id)_\(isDark ? "dark" : "light")"
        if let cached = imageCache[key] {
            return cached
        }

        let b64 = isDark ? theme.darkSvgData : theme.lightSvgData
        guard let data = Data(base64Encoded: b64),
              let img = NSImage(data: data) else {
            return nil
        }
        imageCache[key] = img
        return img
    }

    @ViewBuilder
    func thumbnail(for id: String, isDark: Bool, size: CGFloat = 28) -> some View {
        if let img = nsImage(for: id, isDark: isDark) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: size, height: size)
        }
    }

    // MARK: - Persistence
    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let syncBoardDir = appSupport.appendingPathComponent("SyncBoard", isDirectory: true)
        if !FileManager.default.fileExists(atPath: syncBoardDir.path) {
            try? FileManager.default.createDirectory(at: syncBoardDir, withIntermediateDirectories: true)
        }
        return syncBoardDir.appendingPathComponent(storageFileName)
    }

    private func saveThemes() {
        do {
            let data = try JSONEncoder().encode(customThemes)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            print("Failed to save custom art themes: \(error)")
        }
    }

    private func loadThemes() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CustomArtTheme].self, from: data) else {
            return
        }
        customThemes = decoded
    }
}
