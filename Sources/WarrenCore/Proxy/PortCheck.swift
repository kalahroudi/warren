// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

public enum PortCheck {
    /// True if nothing is listening on the TCP port on any address Caddy would bind.
    public static func isFree(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return true }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = INADDR_ANY
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// The command name and pid of whatever is listening on the port, if it can be found.
    public static func holder(of port: Int) -> String? {
        guard let result = try? Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fcp"]),
              result.status == 0 else { return nil }
        var command: String?
        var pid: String?
        for line in result.output.split(separator: "\n") {
            if line.hasPrefix("c") {
                command = String(line.dropFirst())
            }
            if line.hasPrefix("p") {
                pid = String(line.dropFirst())
            }
        }
        guard let command, let pid else { return nil }
        return "\(command) (pid \(pid))"
    }
}
