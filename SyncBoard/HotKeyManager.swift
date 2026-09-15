//
//  HotKeyManager.swift
//  SyncBoard
//

import AppKit
import Carbon.HIToolbox

/// Wraps the Carbon RegisterEventHotKey API to provide a system-wide keyboard
/// shortcut that works even when SyncBoard is not the frontmost app.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onHotKeyPressed?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: fourCharCode("SBRD"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }
}
