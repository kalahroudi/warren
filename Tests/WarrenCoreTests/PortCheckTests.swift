// SPDX-License-Identifier: Apache-2.0

import Darwin
import Testing
@testable import WarrenCore

struct PortCheckTests {
    @Test func detectsAPortInUse() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(
                descriptor,
                $0,
                socklen_t(MemoryLayout<sockaddr_in>.size)
            ) }
        }
        try #require(bound == 0)
        try #require(listen(descriptor, 1) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(descriptor, $0, &length) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))

        #expect(!PortCheck.isFree(port))
        #expect(PortCheck.holder(of: port)?.contains("pid") == true)
    }
}
