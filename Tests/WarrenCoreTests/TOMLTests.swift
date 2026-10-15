// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import WarrenCore

struct TOMLTests {
    @Test func parsesScalarsTablesAndComments() throws {
        let document = try TOML.parse("""
        # comment
        name = "acme"   # trailing
        count = 3
        enabled = true

        [run]
        command = 'pnpm dev'
        """)
        #expect(document.tables[""]?["name"] == .string("acme"))
        #expect(document.tables[""]?["count"] == .integer(3))
        #expect(document.tables[""]?["enabled"] == .bool(true))
        #expect(document.tables["run"]?["command"] == .string("pnpm dev"))
    }

    @Test func parsesStringArrays() throws {
        let document = try TOML.parse("domains = [\"a.test\", 'b.test',]")
        #expect(document.tables[""]?["domains"] == .strings(["a.test", "b.test"]))
    }

    @Test func handlesEscapesInBasicStrings() throws {
        let document = try TOML.parse(#"text = "a\"b\\c""#)
        #expect(document.tables[""]?["text"] == .string(#"a"b\c"#))
    }

    @Test func reportsLineNumbers() {
        #expect(throws: TOMLError(line: 3, message: "unrecognized value")) {
            try TOML.parse("a = 1\n\nb = = 2")
        }
    }

    @Test func rejectsDuplicatesAndMultilineArrays() {
        #expect(throws: TOMLError.self) { try TOML.parse("a = 1\na = 2") }
        #expect(throws: TOMLError.self) { try TOML.parse("[t]\n[t]") }
        #expect(throws: TOMLError.self) { try TOML.parse("a = [\n\"x\"\n]") }
    }

    @Test func rejectsUnterminatedStringsAndTrailingText() {
        #expect(throws: TOMLError.self) { try TOML.parse("a = \"open") }
        #expect(throws: TOMLError.self) { try TOML.parse("a = 1 b") }
    }
}
