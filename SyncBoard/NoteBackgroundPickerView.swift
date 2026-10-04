//
//  NoteBackgroundPickerView.swift
//  SyncBoard
//

import SwiftUI

/// Two-row background customization popover matching Google Keep's design:
/// Row 1: Solid background color swatches with active purple ring + check badge.
/// Row 2: Official Google Keep & User-Uploaded Custom SVG thumbnails (dynamic Light/Dark) with active purple ring + check badge.
struct NoteBackgroundPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var customThemeManager = CustomArtThemeManager.shared

    let selectedColor: NoteColor
    let selectedTheme: NoteTheme
    var selectedCustomThemeId: String? = nil
    let onSelectColor: (NoteColor) -> Void
    let onSelectTheme: (NoteTheme) -> Void
    var onSelectCustomTheme: ((String?) -> Void)? = nil

    private let purpleAccent = Color(red: 0.72, green: 0.38, blue: 0.98)
    private let swatchSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Solid Colors
            HStack(spacing: 8) {
                // Default / No Color
                colorButton(
                    color: .default,
                    customContent: AnyView(
                        ZStack {
                            Circle().fill(Color.primary.opacity(0.1))
                            Image(systemName: "nosign")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.7))
                        }
                    )
                )

                ForEach(NoteColor.allCases.filter { $0 != .default }) { color in
                    colorButton(color: color)
                }
            }

            // Divider between Colors and Themes
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 2)

            // Row 2: Built-in and Custom SVG Themes
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // No Theme
                    themeButton(
                        theme: .none,
                        customContent: AnyView(
                            ZStack {
                                Circle().fill(Color.primary.opacity(0.1))
                                Image(systemName: "photo")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.7))
                            }
                        )
                    )

                    // 9 Built-in Google Keep Themes
                    ForEach(NoteTheme.allCases.filter { $0 != .none }) { theme in
                        themeButton(theme: theme)
                    }

                    // User Custom Uploaded Themes
                    if !customThemeManager.customThemes.isEmpty {
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 1, height: swatchSize - 6)
                            .padding(.horizontal, 2)

                        ForEach(customThemeManager.customThemes) { customTheme in
                            customThemeButton(customTheme: customTheme)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Color Button
    private func colorButton(color: NoteColor, customContent: AnyView? = nil) -> some View {
        let isSelected = selectedColor == color
        return Button {
            onSelectColor(color)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let customContent = customContent {
                        customContent
                    } else {
                        Circle()
                            .fill(color.swatch)
                    }
                }
                .frame(width: swatchSize, height: swatchSize)
                .overlay(
                    Circle()
                        .stroke(isSelected ? purpleAccent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 0.8)
                )

                if isSelected {
                    checkmarkBadge
                }
            }
        }
        .buttonStyle(.plain)
        .help(color.displayName)
    }

    // MARK: - Theme Button
    private func themeButton(theme: NoteTheme, customContent: AnyView? = nil) -> some View {
        let isSelected = selectedCustomThemeId == nil && selectedTheme == theme
        return Button {
            onSelectCustomTheme?(nil)
            onSelectTheme(theme)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let customContent = customContent {
                        customContent
                    } else {
                        KeepThemeAssets.thumbnail(for: theme, isDark: colorScheme == .dark, size: swatchSize)
                    }
                }
                .frame(width: swatchSize, height: swatchSize)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? purpleAccent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 0.8)
                )

                if isSelected {
                    checkmarkBadge
                }
            }
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
    }

    // MARK: - Custom Theme Button
    private func customThemeButton(customTheme: CustomArtTheme) -> some View {
        let isSelected = selectedCustomThemeId == customTheme.id
        return Button {
            onSelectTheme(.none)
            onSelectCustomTheme?(customTheme.id)
        } label: {
            ZStack(alignment: .topTrailing) {
                customThemeManager.thumbnail(for: customTheme.id, isDark: colorScheme == .dark, size: swatchSize)
                    .frame(width: swatchSize, height: swatchSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isSelected ? purpleAccent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 0.8)
                    )

                if isSelected {
                    checkmarkBadge
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(customTheme.name) (Custom SVG)")
    }

    // MARK: - Checkmark Badge
    private var checkmarkBadge: some View {
        ZStack {
            Circle()
                .fill(purpleAccent)
                .frame(width: 12, height: 12)
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
        }
        .offset(x: 2, y: -2)
    }
}
