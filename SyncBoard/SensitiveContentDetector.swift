//
//  SensitiveContentDetector.swift
//  SyncBoard
//

import Foundation

/// Flags text that's likely a password, API key, token, credit card, or other secret,
/// so the UI can mask it by default instead of showing it in plain sight.
enum SensitiveContentDetector {
    /// Prefixes used by common providers' API keys/tokens — a match here is
    /// treated as sensitive regardless of the length/entropy heuristics.
    private static let knownPrefixes = [
        "GOCSPX-", "sk-", "sk_live_", "sk_test_", "pk_live_", "pk_test_",
        "AIza", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_",
        "xoxb-", "xoxp-", "xoxa-", "xoxr-", "xoxs-",
        "AKIA", "ASIA", "-----BEGIN", "eyJ", "Bearer "
    ]

    static func looksSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        if knownPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }
        if looksLikeToken(trimmed) || looksLikePassword(trimmed) || looksLikeCreditCard(trimmed) {
            return true
        }
        
        // Check if multi-word text contains any sensitive token/secret
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if tokens.count > 1 {
            return tokens.contains { looksSensitiveSingle($0) }
        }
        
        return false
    }

    private static func looksSensitiveSingle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if knownPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }
        return looksLikeToken(trimmed) || looksLikePassword(trimmed) || looksLikeCreditCard(trimmed)
    }

    /// Masks sensitive content.
    static func mask(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        if tokens.count > 1 && tokens.contains(where: { looksSensitiveSingle($0) }) {
            var result = text
            for token in tokens where looksSensitiveSingle(token) {
                result = result.replacingOccurrences(of: token, with: maskSingle(token))
            }
            return result
        }
        
        return maskSingle(trimmed)
    }

    private static func maskSingle(_ text: String) -> String {
        guard text.count > 2 else {
            return String(repeating: "•", count: max(text.count, 4))
        }
        return "\(text.first!)\(String(repeating: "•", count: 8))\(text.last!)"
    }

    /// Long, single-token strings mixing letters and digits with no spaces
    /// read as API keys or access tokens rather than prose.
    private static func looksLikeToken(_ text: String) -> Bool {
        guard text.count >= 20, text.count <= 512, !text.contains(where: \.isWhitespace) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./+=\\|"))
        guard text.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return text.contains(where: \.isLetter) && text.contains(where: \.isNumber)
    }

    /// Short, single-line strings mixing case, digits, and symbols read as
    /// generated passwords (e.g. from a password manager).
    private static func looksLikePassword(_ text: String) -> Bool {
        guard text.count >= 8, text.count <= 64, !text.contains(where: \.isWhitespace) else { return false }
        let categories = [
            text.contains(where: \.isUppercase),
            text.contains(where: \.isLowercase),
            text.contains(where: \.isNumber),
            text.contains(where: { !$0.isLetter && !$0.isNumber })
        ].filter { $0 }.count
        return categories >= 3
    }

    /// 13-19 digit sequences matching standard credit card number lengths.
    private static func looksLikeCreditCard(_ text: String) -> Bool {
        let cleanDigits = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        guard cleanDigits.count >= 13, cleanDigits.count <= 19, cleanDigits.allSatisfy(\.isNumber) else { return false }
        return true
    }
}
