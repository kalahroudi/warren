// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
@testable import WarrenCore

/// A `launchctl` stand-in that records what was asked and never starts a real job.
final class FakeLaunch: LaunchControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var loadedLabels: Set<String> = []
    private var recorded: [String] = []
    private var infos: [String: JobInfo] = [:]

    var calls: [String] {
        lock.withLock { recorded }
    }

    func setLoaded(_ label: String) {
        _ = lock.withLock { loadedLabels.insert(label) }
    }

    /// What `info` reports for a loaded job; running by default.
    func setInfo(_ label: String, _ info: JobInfo) {
        lock.withLock { infos[label] = info }
    }

    func bootstrap(plist: URL) throws {
        let data = try? Data(contentsOf: plist)
        let dictionary = data
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
        lock.withLock {
            recorded.append("bootstrap \(plist.lastPathComponent)")
            loadedLabels.insert(dictionary?["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent)
        }
    }

    func info(label: String) -> JobInfo? {
        lock.withLock { loadedLabels.contains(label) ? infos[label] ?? JobInfo(running: true) : nil }
    }

    func bootout(label: String) throws {
        lock.withLock {
            recorded.append("bootout \(label)")
            loadedLabels.remove(label)
        }
    }

    func isLoaded(label: String) -> Bool {
        lock.withLock { loadedLabels.contains(label) }
    }
}

/// A TCP socket listening on an ephemeral loopback port. Close the descriptor when done.
func listeningSocket() throws -> (descriptor: Int32, port: Int) {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(
            descriptor,
            $0,
            socklen_t(MemoryLayout<sockaddr_in>.size)
        ) }
    }
    guard bound == 0, listen(descriptor, 128) == 0 else {
        close(descriptor)
        throw POSIXError(.EADDRINUSE)
    }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(descriptor, $0, &length) }
    }
    return (descriptor, Int(UInt16(bigEndian: address.sin_port)))
}

func temporaryDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("warren-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
