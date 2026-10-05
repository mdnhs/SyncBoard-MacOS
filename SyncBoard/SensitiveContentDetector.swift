//
//  SensitiveContentDetector.swift
//  SyncBoard
//

import Foundation

/// Flags text that's likely a password, API key, token, credit card, or other secret,
/// so the UI can mask it by default instead of showing it in plain sight.
///
/// Inside longer text only strong signals count (known key formats, long random
/// tokens, card numbers, labelled secrets); the looser password heuristic only
/// applies to a lone copied string, so prose, URLs, and code aren't masked.
enum SensitiveContentDetector {
    /// Prefixes used by common providers' API keys/tokens.
    private static let knownPrefixes = [
        "GOCSPX-", "sk-", "sk_live_", "sk_test_", "pk_live_", "pk_test_", "rk_live_",
        "AIza", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_", "glpat-",
        "xoxb-", "xoxp-", "xoxa-", "xoxr-", "xoxs-",
        "AKIA", "ASIA", "eyJ"
    ]
    /// A bare prefix like "ASIAN" or "sk-learn" isn't a key; real ones are much longer.
    private static let minimumPrefixedTokenLength = 16

    private static let tokenPattern = try! NSRegularExpression(pattern: #"\S+"#)
    private static let labelledSecretPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:password|passwd|pwd|passcode|secret|token|api[ _-]?key|access[ _-]?key|client[ _-]?secret|pin)\b\s*[:=]\s*(\S{4,})|\bbearer\s+(\S{8,})"#
    )
    private static let cardNumberPattern = try! NSRegularExpression(pattern: #"(?<![\d-])(?:\d[ -]?){12,18}\d(?![\d-])"#)
    private static let pemPattern = try! NSRegularExpression(
        pattern: #"-----BEGIN [A-Z0-9 ]+-----[\s\S]*?(?:-----END [A-Z0-9 ]+-----|$)"#
    )
    private static let hostPortPattern = try! NSRegularExpression(pattern: #"^[A-Za-z0-9.-]+:\d{2,5}(?:/\S*)?$"#)
    private static let emailPattern = try! NSRegularExpression(pattern: #"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#)
    private static let codePattern = try! NSRegularExpression(pattern: #"[A-Za-z_]\w*\(.*\)|=>|->|==|&&|\|\|"#)
    private static let assignmentPattern = try! NSRegularExpression(pattern: #"^([A-Za-z_][A-Za-z0-9_]*)[=:](\S+)$"#)
    private static let isoDatePattern = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}(?:T[\d:.]+(?:Z|[+-]\d{2}:?\d{2})?)?$"#)

    static func looksSensitive(_ text: String) -> Bool {
        !sensitiveRanges(in: text).isEmpty
    }

    /// Masks only the sensitive parts, so a note with one key in it stays readable.
    static func mask(_ text: String) -> String {
        let ranges = sensitiveRanges(in: text)
        guard !ranges.isEmpty else {
            // Text can be flagged for other reasons, e.g. a password manager's concealed copy.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? text : maskSingle(trimmed)
        }
        var result = ""
        var cursor = text.startIndex
        for range in ranges {
            result += text[cursor..<range.lowerBound]
            result += maskSingle(String(text[range]))
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    // MARK: - Detection

    private static func sensitiveRanges(in text: String) -> [Range<String.Index>] {
        let tokens = matches(of: tokenPattern, in: text)
        guard !tokens.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        if tokens.count == 1 {
            if let range = secretRange(in: tokens[0], of: text) {
                return [range]
            }
            if looksLikePassword(String(text[tokens[0]])) {
                return [tokens[0]]
            }
        } else {
            for range in tokens {
                let core = trimmingEdgePunctuation(range, in: text)
                if !core.isEmpty, let secret = secretRange(in: core, of: text) {
                    ranges.append(secret)
                }
            }
        }

        ranges += matches(of: labelledSecretPattern, in: text, captureGroups: [1, 2])
            .map { trimmingEdgePunctuation($0, in: text) }
            .filter { !$0.isEmpty }
        ranges += matches(of: cardNumberPattern, in: text).filter { passesLuhn(String(text[$0])) }
        ranges += matches(of: pemPattern, in: text)
        return merged(ranges)
    }

    /// For `NAME=value` only the value is secret, so the variable name stays readable.
    private static func secretRange(in range: Range<String.Index>, of text: String) -> Range<String.Index>? {
        let token = String(text[range])
        if !token.contains("://"),
           let match = assignmentPattern.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
           let keyRange = Range(match.range(at: 1), in: token),
           let valueRange = Range(match.range(at: 2), in: token) {
            let key = token[keyRange].lowercased()
            let value = String(token[valueRange])
            let keyNamesSecret = ["key", "token", "secret", "password", "passwd", "pwd"].contains { key.contains($0) }
            guard isSecretToken(value) || (keyNamesSecret && value.count >= 4) else { return nil }
            let offset = token.distance(from: token.startIndex, to: valueRange.lowerBound)
            return text.index(range.lowerBound, offsetBy: offset)..<range.upperBound
        }
        return isSecretToken(token) ? range : nil
    }

    /// Strong signals that hold even inside prose.
    private static func isSecretToken(_ token: String) -> Bool {
        if token.count >= minimumPrefixedTokenLength, knownPrefixes.contains(where: { token.hasPrefix($0) }) {
            return true
        }
        if token.contains("://") {
            return urlCarriesSecret(token)
        }
        return looksLikeToken(token)
    }

    /// Long, single-token strings of random-looking letters and digits read as
    /// API keys or access tokens. Identifiers built from words
    /// (`user_profile_settings_v2`) don't count.
    private static func looksLikeToken(_ text: String) -> Bool {
        guard text.count >= 20, text.count <= 512 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./+=\\|"))
        guard text.unicodeScalars.allSatisfy(allowed.contains),
              text.contains(where: \.isLetter), text.contains(where: \.isNumber) else { return false }
        let segments = text.split { "-_./+=\\|".contains($0) }
        return !segments.allSatisfy(isWordLikeSegment)
    }

    /// Lone copied strings that look generated: several character classes,
    /// frequent switches between them, and letters that don't form words.
    private static func looksLikePassword(_ text: String) -> Bool {
        guard text.count >= 8, text.count <= 64, !text.contains(where: \.isWhitespace) else { return false }
        guard !looksStructured(text) else { return false }

        let classes = text.map(characterClass)
        guard Set(classes).count >= 3 else { return false }

        let letterRuns = text.split { !$0.isLetter }
        let longestRun = letterRuns.map(\.count).max() ?? 0
        if letterRuns.allSatisfy(isWordLikeRun), longestRun >= 4 {
            return false
        }

        let switches = zip(classes, classes.dropFirst()).count { $0 != $1 }
        return Double(switches) / Double(classes.count - 1) >= 0.3
    }

    /// URLs, emails, paths, `host:port`, dates/versions, and code.
    private static func looksStructured(_ text: String) -> Bool {
        if text.contains("://") || text.lowercased().hasPrefix("www.") { return true }
        if text.hasPrefix("/") || text.hasPrefix("~/") || text.hasPrefix("./") { return true }
        if containsMatch(emailPattern, text) || containsMatch(hostPortPattern, text) || containsMatch(isoDatePattern, text) { return true }
        if containsMatch(codePattern, text) { return true }
        if text.allSatisfy({ $0.isNumber || "-./:,+()".contains($0) }) { return true }
        if let first = text.first, let last = text.last, "{[(<\"'`".contains(first), "}])>\"'`;".contains(last) {
            return true
        }
        return false
    }

    private static func urlCarriesSecret(_ text: String) -> Bool {
        guard let components = URLComponents(string: text) else { return false }
        if let password = components.password, !password.isEmpty { return true }
        let secretNames: Set<String> = ["token", "access_token", "id_token", "refresh_token", "api_key", "apikey", "key", "secret", "client_secret", "password", "sig", "signature"]
        return (components.queryItems ?? []).contains { item in
            guard let value = item.value, !value.isEmpty else { return false }
            return (secretNames.contains(item.name.lowercased()) && value.count >= 8) || looksLikeToken(value)
        }
    }

    // MARK: - Helpers

    private enum CharacterClass { case upper, lower, digit, symbol }

    private static func characterClass(_ character: Character) -> CharacterClass {
        if character.isNumber { return .digit }
        if character.isUppercase { return .upper }
        if character.isLowercase { return .lower }
        return .symbol
    }

    /// `word`, `Word`, or `WORD`, as opposed to `wOrD`.
    private static func isWordLikeRun(_ run: Substring) -> Bool {
        let rest = run.dropFirst()
        return run.allSatisfy(\.isLowercase) || run.allSatisfy(\.isUppercase)
            || (run.first?.isUppercase == true && rest.allSatisfy(\.isLowercase))
    }

    /// A word optionally followed by digits (`settings`, `v2`, `utf8`), or plain digits.
    private static func isWordLikeSegment(_ segment: Substring) -> Bool {
        if segment.allSatisfy(\.isNumber) { return true }
        let letters = segment.prefix { $0.isLetter }
        let digits = segment.dropFirst(letters.count)
        return !letters.isEmpty && isWordLikeRun(letters) && digits.allSatisfy(\.isNumber)
    }

    private static func trimmingEdgePunctuation(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        let edges = Set("()[]{}<>\"'`.,;:!?")
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, edges.contains(text[lower]) { lower = text.index(after: lower) }
        while upper > lower, edges.contains(text[text.index(before: upper)]) { upper = text.index(before: upper) }
        return lower..<upper
    }

    private static func passesLuhn(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, pair in
            let (index, digit) = pair
            guard index.isMultiple(of: 2) else {
                let doubled = digit * 2
                return total + (doubled > 9 ? doubled - 9 : doubled)
            }
            return total + digit
        }
        return sum.isMultiple(of: 10)
    }

    private static func matches(of pattern: NSRegularExpression, in text: String, captureGroups: [Int] = [0]) -> [Range<String.Index>] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { match in
            captureGroups.compactMap { group in
                guard group < match.numberOfRanges, match.range(at: group).location != NSNotFound else { return nil }
                return Range(match.range(at: group), in: text)
            }
        }
    }

    private static func containsMatch(_ pattern: NSRegularExpression, _ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func merged(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        ranges.sorted { $0.lowerBound < $1.lowerBound }.reduce(into: []) { result, range in
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
    }

    private static func maskSingle(_ text: String) -> String {
        guard text.count > 2, let first = text.first, let last = text.last else {
            return String(repeating: "•", count: max(text.count, 4))
        }
        return "\(first)\(String(repeating: "•", count: 8))\(last)"
    }
}
