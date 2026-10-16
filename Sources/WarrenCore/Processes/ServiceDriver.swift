// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How Warren tells that a service is ready to be used.
public enum ServiceReadiness: Equatable, Sendable {
    /// Something accepts TCP connections on the port.
    case port(Int)
    /// The command exits with status 0, such as `pg_isready`.
    case command([String])
}

/// What a client needs to reach a running service.
public struct ServiceConnection: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let user: String?
    /// A connection string with the details filled in, when the service has a standard one.
    public let url: String?

    public init(host: String = "127.0.0.1", port: Int, user: String? = nil, url: String? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.url = url
    }
}

/// One service Warren runs: a program, where its data lives and how to tell it is ready. The catalog (018) supplies
/// these facts as data; nothing here is specific to one service.
public struct ServiceInstance: Equatable, Sendable {
    public let id: String
    public let name: String
    public let program: String
    public let arguments: [String]
    public let environment: [String: String]
    /// Its data folder, created before the first start.
    public let dataDirectory: URL
    public let readiness: ServiceReadiness
    public let connection: ServiceConnection?

    public init(
        id: String, name: String, program: String, arguments: [String] = [], environment: [String: String] = [:],
        dataDirectory: URL, readiness: ServiceReadiness, connection: ServiceConnection? = nil
    ) {
        self.id = id
        self.name = name
        self.program = program
        self.arguments = arguments
        self.environment = environment
        self.dataDirectory = dataDirectory
        self.readiness = readiness
        self.connection = connection
    }
}

public enum ServiceState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case crashed(exitCode: Int32?)
}

public enum ServiceStartError: Error, Equatable, LocalizedError, Sendable {
    case exited(code: Int32?, lastLines: [String])
    case notReady(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .exited(code, lines):
            "it stopped right after starting" + (code.map { " (exit status \($0))" } ?? "")
                + (lines.last.map { ": \($0)" } ?? "")
        case let .notReady(seconds): "it was not ready after \(seconds) seconds. See its log."
        }
    }
}

/// Runs services. The native driver is here; the container driver (019) implements the same interface.
public protocol ServiceDriver: Sendable {
    /// `"native"`, later `"container"`.
    var kind: String { get }
    func status(of service: ServiceInstance) async -> ServiceState
    /// Returns once the service is ready. Does nothing if it is already running.
    func start(_ service: ServiceInstance) async throws
    func stop(_ service: ServiceInstance) async throws
    func logs(of service: ServiceInstance) -> URL
    /// Nil if the service has no network address to give.
    func connection(of service: ServiceInstance) -> ServiceConnection?
}

/// Runs a service as a program on this Mac, as a launchd job started on request, like a site's server.
public struct NativeDriver: ServiceDriver {
    public let kind = "native"
    public let paths: WarrenPaths
    private let host: JobHost
    private let timeout: TimeInterval

    public init(paths: WarrenPaths, launch: any LaunchControlling = LaunchCtl(), timeout: TimeInterval = 60) {
        self.paths = paths
        host = JobHost(paths: paths, launch: launch)
        self.timeout = timeout
    }

    private func label(_ service: ServiceInstance) -> String {
        "dev.warren.service.\(service.id)"
    }

    private func stem(_ service: ServiceInstance) -> String {
        "service-\(service.id)"
    }

    public func logs(of service: ServiceInstance) -> URL {
        paths.logsDirectory.appendingPathComponent("service-\(service.id).log")
    }

    public func connection(of service: ServiceInstance) -> ServiceConnection? {
        service.connection
    }

    public func status(of service: ServiceInstance) async -> ServiceState {
        guard host.hasPlist(stem: stem(service)), let info = host.info(label: label(service)) else { return .stopped }
        guard info.running else { return .crashed(exitCode: info.lastExit) }
        return isReady(service) ? .running : .starting
    }

    public func start(_ service: ServiceInstance) async throws {
        switch await status(of: service) {
        case .running, .starting: return
        default: break
        }
        try FileManager.default.createDirectory(at: service.dataDirectory, withIntermediateDirectories: true)
        let job = ManagedJob(
            label: label(service), stem: stem(service), program: service.program, arguments: service.arguments,
            environment: service.environment, directory: service.dataDirectory.path, logFile: logs(of: service)
        )
        try host.start(job)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isReady(service) {
                return
            }
            if let info = host.info(label: job.label), !info.running {
                throw ServiceStartError.exited(code: info.lastExit, lastLines: tail(logs(of: service)))
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw ServiceStartError.notReady(seconds: Int(timeout))
    }

    public func stop(_ service: ServiceInstance) async throws {
        try host.stop(label: label(service), stem: stem(service))
    }

    private func isReady(_ service: ServiceInstance) -> Bool {
        switch service.readiness {
        case let .port(port): PortCheck.isListening(port)
        case let .command(command):
            command.first.flatMap { try? Shell.run($0, Array(command.dropFirst())) }?.status == 0
        }
    }

    private func tail(_ file: URL) -> [String] {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return Array(text.split(separator: "\n").suffix(8).map(String.init))
    }
}
