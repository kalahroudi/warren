// SPDX-License-Identifier: Apache-2.0

import Foundation

/// `major.minor.patch`, with missing parts read as zero.
struct SemanticVersion: Comparable, Hashable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts `22`, `22.1`, `v22.1.3`. Anything with a pre-release suffix or other text is rejected.
    init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1 ... 3).contains(parts.count), !parts.contains(nil) else { return nil }
        let numbers = parts.compactMap(\.self)
        self.init(numbers[0], numbers.count > 1 ? numbers[1] : 0, numbers.count > 2 ? numbers[2] : 0)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var text: String {
        "\(major).\(minor).\(patch)"
    }
}

/// The version ranges `package.json` `engines` uses: `>=20`, `^20.1`, `~20.1.0`, `20.x`, `>=18 <23`, `18 || 20`.
/// Pre-release tags and hyphen ranges are not supported, and make the range unreadable (nil).
struct VersionRange: Sendable {
    /// Half-open interval `[lower, upper)`. A nil bound is open.
    private struct Interval {
        var lower: SemanticVersion?
        var upper: SemanticVersion?

        func contains(_ version: SemanticVersion) -> Bool {
            (lower.map { version >= $0 } ?? true) && (upper.map { version < $0 } ?? true)
        }
    }

    private let alternatives: [[Interval]]

    init?(_ text: String) {
        var alternatives: [[Interval]] = []
        for alternative in text.components(separatedBy: "||") {
            var tokens = alternative.split(whereSeparator: \.isWhitespace).map(String.init)
            // ">= 18" is written with a space in some files.
            var index = 0
            while index < tokens.count - 1 {
                if [">=", "<=", ">", "<", "=", "^", "~"].contains(tokens[index]) {
                    tokens[index] += tokens.remove(at: index + 1)
                }
                index += 1
            }
            guard !tokens.isEmpty else { return nil }
            var intervals: [Interval] = []
            for token in tokens {
                guard let interval = Self.interval(for: token) else { return nil }
                intervals.append(interval)
            }
            alternatives.append(intervals)
        }
        guard !alternatives.isEmpty else { return nil }
        self.alternatives = alternatives
    }

    /// Composer's constraint syntax: `^8.2`, `>=8.1,<8.4`, `8.2.*`, `~8.2`, `8.1 | 8.3`. Comma and space both mean
    /// "and". `~8.2` allows any 8.x from 8.2 on, which is npm's `^8.2`; `~8.2.1` matches npm's `~`.
    init?(composer text: String) {
        let normalized = text
            .replacingOccurrences(of: "||", with: "\u{1}")
            .replacingOccurrences(of: "|", with: "\u{1}")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "\u{1}", with: " || ")
        let rewritten = normalized.components(separatedBy: " || ").map { alternative in
            alternative.split(whereSeparator: \.isWhitespace).map { token -> String in
                let body = token.dropFirst()
                let isTwoPartTilde = token.hasPrefix("~") && body.split(separator: ".").count == 2
                return isTwoPartTilde ? "^" + body : String(token)
            }.joined(separator: " ")
        }.joined(separator: " || ")
        self.init(rewritten)
    }

    /// PEP 440 specifiers as `requires-python` writes them: `>=3.10`, `>=3.10,<3.13`, `==3.12.*`, `~=3.11`.
    /// `~=3.11` allows any 3.x from 3.11 (npm's `^3.11`); `~=3.11.2` stays within 3.11 (npm's `~`). `!=`, `===` and
    /// pre-release markers are not supported and make the range unreadable.
    init?(pep440 text: String) {
        let tokens = text.replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace)
        var merged: [String] = []
        for token in tokens {
            if let last = merged.last, ["<", ">", "<=", ">=", "==", "~="].contains(last) {
                merged[merged.count - 1] = last + token
            } else {
                merged.append(String(token))
            }
        }
        let rewritten = merged.map { token -> String in
            if token.hasPrefix("~=") {
                let body = token.dropFirst(2)
                return (body.split(separator: ".").count == 2 ? "^" : "~") + body
            }
            if token.hasPrefix("===") {
                return "!" // arbitrary equality is not supported
            }
            return token.hasPrefix("==") ? String(token.dropFirst(2)) : token
        }
        self.init(rewritten.joined(separator: " "))
    }

    func contains(_ version: SemanticVersion) -> Bool {
        alternatives.contains { $0.allSatisfy { $0.contains(version) } }
    }

    private static let operators = [">=", "<=", ">", "<", "=", "^", "~"]

    private static func interval(for token: String) -> Interval? {
        let comparison = operators.first { token.hasPrefix($0) } ?? ""
        let body = String(token.dropFirst(comparison.count))
        if body == "*" || body.lowercased() == "x" {
            return Interval()
        }
        let parts = body.hasPrefix("v") ? body.dropFirst().split(separator: ".", omittingEmptySubsequences: false)
            : body.split(separator: ".", omittingEmptySubsequences: false)
        // How many leading parts are numbers; "x" and "*" end the list.
        var numbers: [Int] = []
        for part in parts {
            if ["x", "X", "*"].contains(part) {
                break
            }
            guard let number = Int(part) else { return nil }
            numbers.append(number)
        }
        guard (1 ... 3).contains(numbers.count) else { return nil }
        let low = SemanticVersion(numbers[0], numbers.count > 1 ? numbers[1] : 0, numbers.count > 2 ? numbers[2] : 0)
        let next = nextAfter(numbers)

        switch comparison {
        case "", "=": return Interval(lower: low, upper: next)
        case ">=": return Interval(lower: low)
        case ">": return Interval(lower: next)
        case "<": return Interval(upper: low)
        case "<=": return Interval(upper: next)
        case "^":
            if numbers[0] > 0 || numbers
                .count == 1
            {
                return Interval(lower: low, upper: SemanticVersion(numbers[0] + 1))
            }
            return Interval(lower: low, upper: SemanticVersion(0, numbers[1] + 1))
        default: // "~"
            if numbers.count == 1 {
                return Interval(lower: low, upper: SemanticVersion(numbers[0] + 1))
            }
            return Interval(lower: low, upper: SemanticVersion(numbers[0], numbers[1] + 1))
        }
    }

    /// The first version after everything the partial version `numbers` covers: `22` gives 23.0.0, `22.1.3` gives
    /// 22.1.4.
    private static func nextAfter(_ numbers: [Int]) -> SemanticVersion {
        switch numbers.count {
        case 1: SemanticVersion(numbers[0] + 1)
        case 2: SemanticVersion(numbers[0], numbers[1] + 1)
        default: SemanticVersion(numbers[0], numbers[1], numbers[2] + 1)
        }
    }
}
