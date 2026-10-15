// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import WarrenCore

@Test func versionIsSemver() {
    let parts = Warren.version.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
