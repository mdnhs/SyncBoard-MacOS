//
//  DeviceOriginLabel.swift
//  SyncBoard
//

import SwiftUI

/// Shows which device created an item. Renders nothing for items saved
/// before origins were recorded.
struct DeviceOriginLabel: View {
    let origin: DeviceOrigin?
    /// Detail views prefix the name (e.g. "Copied on"); rows and cards show it bare.
    var prefix: String?

    var body: some View {
        if let origin {
            let fullText = [prefix, origin.name].compactMap { $0 }.joined(separator: " ")
                + (origin.isCurrentDevice ? " (this Mac)" : "")
            Label {
                Text(prefix.map { "\($0) \(origin.name)" } ?? origin.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: "laptopcomputer")
            }
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .nativeTooltip(fullText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fullText)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        DeviceOriginLabel(origin: .current)
        DeviceOriginLabel(origin: DeviceOrigin(id: "other", name: "Studio iMac"), prefix: "Created on")
        DeviceOriginLabel(origin: nil)
    }
    .padding()
}
