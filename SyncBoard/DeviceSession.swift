//
//  DeviceSession.swift
//  SyncBoard
//

import Foundation
import SystemConfiguration

/// A single signed-in device, as recorded in the shared `syncboard_devices.json`
/// registry on Google Drive so every device can see who else is connected.
nonisolated struct DeviceSession: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var osName: String
    var osVersion: String
    var loginDate: Date
    var lastSeenAt: Date
}

/// The device a clipboard item, note, or task was created on. The name is
/// captured at creation so it still shows after that device leaves the registry.
nonisolated struct DeviceOrigin: Codable, Hashable {
    let id: String
    let name: String

    static var current: DeviceOrigin {
        DeviceOrigin(id: DeviceIdentity.currentID, name: DeviceIdentity.currentName)
    }

    var isCurrentDevice: Bool { id == DeviceIdentity.currentID }
}

/// Stable identity and descriptive info for the device SyncBoard is running on.
/// Marked `nonisolated` so it can be read from the background `GoogleDriveDeviceService`
/// actor as well as MainActor UI code, since none of its data is actor-affine.
nonisolated enum DeviceIdentity {
    private static let storageKey = "SB_DeviceID"

    static let currentID: String = {
        if let existing = UserDefaults.standard.string(forKey: storageKey) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: storageKey)
        return generated
    }()

    static var currentName: String {
        if let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? {
            return computerName
        }
        return ProcessInfo.processInfo.hostName
    }

    static let osName = "macOS"

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
