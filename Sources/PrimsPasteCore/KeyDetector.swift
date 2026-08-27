// Guess whether a paste is a key/token vs prose.
// Never logs or returns the value — only a boolean, a short kind label, and a reason.
//
// Layers, first hit wins:
//   1. PEM / JWT / well-known vendor prefixes (high precision)
//   2. Long hex blobs (32/40/64)
//   3. High-entropy, almost-no-whitespace token (Shannon)
//   4. Otherwise prose
//
// English with the word "key" in it must stay prose. Prefixes only count as
// their own token (start of string, or after whitespace / quote / equals).

import Foundation

public struct KeyGuess: Equatable, Sendable {
    public var isKey: Bool
    public var kind: String
    public var reason: String

    public init(isKey: Bool, kind: String, reason: String) {
        self.isKey = isKey
        self.kind = kind
        self.reason = reason
    }

    public var label: String {
        if !isKey { return "" }
        switch kind {
        case "pem": return "private key"
        case "jwt": return "JWT"
        case "stripe": return "Stripe secret"
        case "openai": return "OpenAI key"
        case "anthropic": return "Anthropic key"
        case "github": return "GitHub token"
        case "gitlab": return "GitLab token"
        case "slack": return "Slack token"
        case "aws": return "AWS key"
        case "google": return "Google key"
        case "xai": return "xAI key"
        case "hex": return "hex secret"
        default: return "API key"
        }
    }
}

public enum KeyDetector {
    public static func inspect(_ raw: String) -> KeyGuess {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return KeyGuess(isKey: false, kind: "empty", reason: "empty")
        }
        if looksLikePEM(text) {
            return KeyGuess(isKey: true, kind: "pem", reason: "PEM private key block")
        }
        if looksLikeJWT(text) {
            return KeyGuess(isKey: true, kind: "jwt", reason: "three base64url segments")
        }
        if let vendor = vendorKind(in: text) {
            return KeyGuess(isKey: true, kind: vendor.kind, reason: vendor.reason)
        }
        if looksLikeHexBlob(text) {
            return KeyGuess(isKey: true, kind: "hex", reason: "long hex blob")
        }
        if looksLikeEnglishProse(text) {
            return KeyGuess(isKey: false, kind: "prose", reason: "spaces + vowels")
        }
        if looksLikeHighEntropyToken(text) {
            return KeyGuess(isKey: true, kind: "entropy", reason: "high entropy, almost no whitespace")
        }
        return KeyGuess(isKey: false, kind: "prose", reason: "default prose")
    }

    // MARK: - PEM / JWT / hex

    private static func looksLikePEM(_ text: String) -> Bool {
        let u = text.uppercased()
        return u.contains("BEGIN") && u.contains("PRIVATE KEY")
    }

    private static func looksLikeJWT(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("eyJ") || t.hasPrefix("eyj") else { return false }
        return jwtShape(t)
    }

    private static func jwtShape(_ t: String) -> Bool {
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return parts.allSatisfy { p in
            p.count >= 8 && p.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    private static func looksLikeHexBlob(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count == 32 || t.count == 40 || t.count == 64 else { return false }
        return t.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    // MARK: - vendor prefixes (as their own token)

    private static let vendors: [(prefix: String, kind: String, reason: String)] = [
        ("sk-ant-", "anthropic", "Anthropic sk-ant- prefix"),
        ("sk-proj-", "openai", "OpenAI project key prefix"),
        ("sk-live-", "stripe", "Stripe live secret prefix"),
        ("sk-test-", "stripe", "Stripe test secret prefix"),
        ("sk-", "openai", "OpenAI sk- prefix"),
        ("rk_live_", "stripe", "Stripe restricted key"),
        ("rk_test_", "stripe", "Stripe restricted test key"),
        ("xai-", "xai", "xAI prefix"),
        ("github_pat_", "github", "GitHub fine-grained pat"),
        ("ghp_", "github", "GitHub PAT"),
        ("gho_", "github", "GitHub oauth token"),
        ("ghs_", "github", "GitHub server token"),
        ("glpat-", "gitlab", "GitLab PAT"),
        ("xoxb-", "slack", "Slack bot token"),
        ("xoxp-", "slack", "Slack user token"),
        ("xoxa-", "slack", "Slack app token"),
        ("xoxs-", "slack", "Slack session token"),
        ("akia", "aws", "AWS access key id"),
        ("asia", "aws", "AWS STS key id"),
        ("aiza", "google", "Google API key"),
    ]

    private static func vendorKind(in text: String) -> (kind: String, reason: String)? {
        let lower = text.lowercased()
        for v in vendors {
            if tokenHasPrefix(lower, prefix: v.prefix) {
                return (v.kind, v.reason)
            }
        }
        return nil
    }

    /// True if `prefix` appears as a token, not as a substring of English.
    private static func tokenHasPrefix(_ lower: String, prefix: String) -> Bool {
        if lower.hasPrefix(prefix) { return remainderLooksLikeSecret(lower, after: prefix) }
        let seps = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'=:,;()[]{}"))
        var i = lower.startIndex
        while i < lower.endIndex {
            if lower[i...].hasPrefix(prefix) {
                let okStart: Bool
                if i == lower.startIndex {
                    okStart = true
                } else {
                    let prev = lower[lower.index(before: i)]
                    okStart = prev.unicodeScalars.allSatisfy { seps.contains($0) }
                }
                if okStart, remainderLooksLikeSecret(String(lower[i...]), after: prefix) {
                    return true
                }
            }
            i = lower.index(after: i)
        }
        return false
    }

    private static func remainderLooksLikeSecret(_ s: String, after prefix: String) -> Bool {
        guard s.hasPrefix(prefix) else { return false }
        let rest = s.dropFirst(prefix.count)
        let token = rest.prefix { !$0.isWhitespace && $0 != "\"" && $0 != "'" }
        // Vendor keys are long random tails, not "sk-im a sentence".
        return token.count >= 12
    }

    // MARK: - prose vs entropy

    private static func looksLikeEnglishProse(_ text: String) -> Bool {
        let spaces = text.reduce(0) { $1 == " " || $1 == "\n" || $1 == "\t" ? $0 + 1 : $0 }
        let letters = text.filter(\.isLetter)
        guard letters.count >= 8 else { return false }
        let vowels = letters.reduce(0) { "aeiouAEIOU".contains($1) ? $0 + 1 : $0 }
        let vowelRatio = Double(vowels) / Double(letters.count)
        let spaceRatio = Double(spaces) / Double(max(text.count, 1))
        // Real sentences have several spaces and a human vowel ratio.
        return spaces >= 2 && spaceRatio >= 0.08 && vowelRatio >= 0.28 && vowelRatio <= 0.52
    }

    private static func looksLikeHighEntropyToken(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.count >= 20 else { return false }
        let ws = Double(text.count - compact.count) / Double(max(text.count, 1))
        guard ws < 0.05 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/_+=.-"))
        let ok = compact.unicodeScalars.filter { allowed.contains($0) }.count
        guard Double(ok) / Double(compact.count) >= 0.9 else { return false }
        return shannon(compact) >= 3.3
    }

    public static func shannon(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0.0) { acc, c in
            let p = Double(c) / n
            return acc - p * log2(p)
        }
    }
}
