// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case strings([String])
}

public struct TOMLError: Error, Equatable, LocalizedError, Sendable {
    public let line: Int
    public let message: String

    public var errorDescription: String? {
        "line \(line): \(message)"
    }
}

/// A parsed document: `tables[""]` holds top-level keys, other keys are `[table]` names.
public struct TOMLDocument: Equatable, Sendable {
    public var tables: [String: [String: TOMLValue]] = ["": [:]]
}

/// A deliberately small TOML subset: comments, `[tables]`, strings, integers, booleans
/// and single-line arrays of strings.
public enum TOML {
    public static func parse(_ text: String) throws -> TOMLDocument {
        var document = TOMLDocument()
        var table = ""
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = offset + 1
            var scanner = Scanner(String(rawLine), line: number)
            scanner.skipSpaces()
            if scanner.atEnd || scanner.peek == "#" {
                continue
            }
            if scanner.peek == "[" {
                table = try scanner.parseTableHeader()
                if document
                    .tables[table] != nil
                {
                    throw TOMLError(line: number, message: "duplicate table [\(table)]")
                }
                document.tables[table] = [:]
                try scanner.expectEndOfLine()
                continue
            }
            let key = try scanner.parseKey()
            scanner.skipSpaces()
            guard scanner.consume("=")
            else { throw TOMLError(line: number, message: "expected '=' after key '\(key)'") }
            scanner.skipSpaces()
            let value = try scanner.parseValue()
            try scanner.expectEndOfLine()
            if document.tables[table]?[key] != nil {
                throw TOMLError(line: number, message: "duplicate key '\(key)'")
            }
            document.tables[table]?[key] = value
        }
        return document
    }
}

private struct Scanner {
    private let chars: [Character]
    private var index = 0
    let line: Int

    init(_ text: String, line: Int) {
        chars = Array(text)
        self.line = line
    }

    var atEnd: Bool {
        index >= chars.count
    }

    var peek: Character? {
        atEnd ? nil : chars[index]
    }

    mutating func skipSpaces() {
        while let char = peek, char == " " || char == "\t" || char == "\r" {
            index += 1
        }
    }

    mutating func consume(_ char: Character) -> Bool {
        guard peek == char else { return false }
        index += 1
        return true
    }

    func fail(_ message: String) -> TOMLError {
        TOMLError(line: line, message: message)
    }

    mutating func expectEndOfLine() throws {
        skipSpaces()
        if atEnd || peek == "#" {
            return
        }
        throw fail("unexpected text after value")
    }

    mutating func parseTableHeader() throws -> String {
        _ = consume("[")
        if peek == "[" {
            throw fail("arrays of tables are not supported")
        }
        var name = ""
        while let char = peek, char != "]" {
            name.append(char)
            index += 1
        }
        guard consume("]") else { throw fail("unterminated table header") }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(".") else { throw fail("only simple table names are supported") }
        return trimmed
    }

    mutating func parseKey() throws -> String {
        var key = ""
        while let char = peek, char.isLetter || char.isNumber || char == "_" || char == "-" {
            key.append(char)
            index += 1
        }
        guard !key.isEmpty else { throw fail("expected a key") }
        return key
    }

    mutating func parseValue() throws -> TOMLValue {
        guard let char = peek else { throw fail("missing value") }
        switch char {
        case "\"", "'": return try .string(parseString())
        case "[": return try parseArray()
        case "t", "f": return try parseBool()
        default: return try parseInteger()
        }
    }

    mutating func parseString() throws -> String {
        guard let quote = peek else { throw fail("missing string") }
        index += 1
        var result = ""
        while let char = peek {
            index += 1
            if char == quote {
                return result
            }
            if char == "\\", quote == "\"" {
                guard let next = peek else { break }
                index += 1
                switch next {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                default: throw fail("unsupported escape '\\\(next)'")
                }
            } else {
                result.append(char)
            }
        }
        throw fail("unterminated string")
    }

    mutating func parseArray() throws -> TOMLValue {
        _ = consume("[")
        var items: [String] = []
        skipSpaces()
        if consume("]") {
            return .strings(items)
        }
        while true {
            skipSpaces()
            guard peek == "\"" || peek == "'" else {
                throw fail(atEnd ? "multi-line arrays are not supported" : "arrays may only contain strings")
            }
            try items.append(parseString())
            skipSpaces()
            if consume("]") {
                return .strings(items)
            }
            guard consume(",")
            else { throw fail(atEnd ? "multi-line arrays are not supported" : "expected ',' or ']'") }
            skipSpaces()
            if consume("]") {
                return .strings(items)
            }
        }
    }

    mutating func parseBool() throws -> TOMLValue {
        for (word, value) in [("true", true), ("false", false)] where matches(word) {
            index += word.count
            return .bool(value)
        }
        throw fail("unrecognized value")
    }

    func matches(_ word: String) -> Bool {
        let end = index + word.count
        guard end <= chars.count else { return false }
        return String(chars[index ..< end]) == word
    }

    mutating func parseInteger() throws -> TOMLValue {
        var digits = ""
        if peek == "-" || peek == "+" {
            digits.append(chars[index])
            index += 1
        }
        while let char = peek, char.isNumber || char == "_" {
            if char != "_" {
                digits.append(char)
            }
            index += 1
        }
        guard let value = Int(digits) else { throw fail("unrecognized value") }
        return .integer(value)
    }
}
