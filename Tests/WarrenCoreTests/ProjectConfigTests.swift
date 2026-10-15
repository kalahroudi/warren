// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import WarrenCore

struct ProjectConfigTests {
    @Test func readsAFullConfig() throws {
        let config = try ProjectConfig.parse("""
        name = "Acme Store"
        domains = ["Acme.Test", "shop.localhost"]

        [runtime]
        node = "22"

        [run]
        command = "pnpm dev"
        port = 3000

        [services]
        postgres = "17"
        """)
        #expect(config.name == "Acme Store")
        #expect(config.domains == ["acme.test", "shop.localhost"])
        #expect(config.runtimes == ["node": "22"])
        #expect(config.command == "pnpm dev")
        #expect(config.port == 3000)
        #expect(config.services == ["postgres": "17"])
        #expect(config.warnings.isEmpty)
    }

    @Test func unknownKeysAndTablesAreWarnings() throws {
        let config = try ProjectConfig.parse("mystery = true\n[run]\nlauncher = \"x\"\n[extra]\nk = \"v\"")
        #expect(config.warnings.count == 3)
    }

    @Test func wrongTypesAreErrors() {
        #expect(throws: ConfigError.self) { try ProjectConfig.parse("domains = \"notarray\"") }
        #expect(throws: ConfigError.self) { try ProjectConfig.parse("name = 3") }
        #expect(throws: ConfigError.self) { try ProjectConfig.parse("[run]\nport = \"x\"") }
        #expect(throws: ConfigError.invalidPort(99999)) { try ProjectConfig.parse("[run]\nport = 99999") }
    }

    @Test func domainRules() throws {
        #expect(try DomainName.normalize("Acme.TEST") == "acme.test")
        #expect(try DomainName.normalize("a-b.c.localhost") == "a-b.c.localhost")
        for bad in ["acme", "-a.test", "a-.test", "a_b.test", "a..test", "", "a.test."] {
            #expect(throws: ConfigError.self) { try DomainName.normalize(bad) }
        }
    }
}
