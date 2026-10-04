//
//  KeychainStore.swift
//  SyncBoard
//

import CryptoKit
import Foundation

/// Secure, prompt-free local credential storage.
/// Uses AES-256-GCM encryption with user-scoped 0600 POSIX permissions in Application Support.
/// Completely eliminates macOS Keychain ACL and "login password" dialog prompts.
enum KeychainStore {
    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SyncBoard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    private static func fileURL(forKey key: String) -> URL {
        let safeName = key.replacingOccurrences(of: "/", with: "_")
        return storageDirectory.appendingPathComponent("\(safeName).dat")
    }

    private static var symmetricKey: SymmetricKey {
        let salt = NSHomeDirectory() + "-com.nazmulhsourab.SyncBoard.credentials"
        let digest = SHA256.hash(data: Data(salt.utf8))
        return SymmetricKey(data: digest)
    }

    static func set(_ value: String, forKey key: String) {
        let url = fileURL(forKey: key)
        guard let data = value.data(using: .utf8),
              let sealedBox = try? AES.GCM.seal(data, using: symmetricKey),
              let combined = sealedBox.combined else {
            return
        }
        try? combined.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func string(forKey key: String) -> String? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let decryptedData = try? AES.GCM.open(sealedBox, using: symmetricKey),
              let string = String(data: decryptedData, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func removeValue(forKey key: String) {
        let url = fileURL(forKey: key)
        try? FileManager.default.removeItem(at: url)
    }
}
