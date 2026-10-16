// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What launchd says about a loaded job.
public struct JobInfo: Equatable, Sendable {
    public let running: Bool
    public let pid: Int?
    /// The exit status of the last run, nil while it has never exited.
    public let lastExit: Int32?

    public init(running: Bool, pid: Int? = nil, lastExit: Int32? = nil) {
        self.running = running
        self.pid = pid
        self.lastExit = lastExit
    }

    /// Reads the part of `launchctl print` Warren needs.
    static func parse(_ text: String) -> JobInfo {
        func value(_ key: String) -> String? {
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(key + " = ") {
                    return String(trimmed.dropFirst(key.count + 3))
                }
            }
            return nil
        }
        let pid = value("pid").flatMap { Int($0) }
        let exit = value("last exit code").flatMap { Int32($0) }
        return JobInfo(running: value("state") == "running" || pid != nil, pid: pid, lastExit: exit)
    }
}

/// A command run by launchd for a site or a service: started on request, stopped on request, never restarted and
/// never started at login. See spec 015.
public struct ManagedJob: Equatable, Sendable {
    public let label: String
    /// Names the plist: `<stem>.plist` in the run folder.
    public let stem: String
    public let program: String
    public let arguments: [String]
    public let environment: [String: String]
    public let directory: String
    public let logFile: URL

    public init(
        label: String, stem: String, program: String, arguments: [String], environment: [String: String],
        directory: String, logFile: URL
    ) {
        self.label = label
        self.stem = stem
        self.program = program
        self.arguments = arguments
        self.environment = environment
        self.directory = directory
        self.logFile = logFile
    }

    /// `KeepAlive` is off so that a server which exits on a syntax error shows its error instead of restarting in a
    /// loop. `ExitTimeOut` is how long launchd waits after SIGTERM before it kills the process group.
    public func plist() throws -> Data {
        var dictionary: [String: Any] = [
            "Label": label,
            "ProgramArguments": [program] + arguments,
            "WorkingDirectory": directory,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ExitTimeOut": 5,
            "StandardOutPath": logFile.path,
            "StandardErrorPath": logFile.path,
        ]
        if !environment.isEmpty {
            dictionary["EnvironmentVariables"] = environment
        }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}

/// Starts and stops managed jobs. The plists live in Warren's own run folder, not in `~/Library/LaunchAgents`, so
/// nothing comes back at the next login.
public struct JobHost: Sendable {
    public let paths: WarrenPaths
    public let launch: any LaunchControlling

    public init(paths: WarrenPaths, launch: any LaunchControlling = LaunchCtl()) {
        self.paths = paths
        self.launch = launch
    }

    public func plistURL(stem: String) -> URL {
        paths.runDirectory.appendingPathComponent("\(stem).plist")
    }

    public func hasPlist(stem: String) -> Bool {
        FileManager.default.fileExists(atPath: plistURL(stem: stem).path)
    }

    public func info(label: String) -> JobInfo? {
        launch.info(label: label)
    }

    /// Writes the plist, empties the log so it shows only this run, and loads the job. A job with the same label that
    /// is still loaded is stopped first.
    public func start(_ job: ManagedJob) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: paths.runDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try manager.createDirectory(at: job.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        manager.createFile(atPath: job.logFile.path, contents: nil)
        let url = plistURL(stem: job.stem)
        try job.plist().write(to: url, options: .atomic)
        if launch.isLoaded(label: job.label) {
            try launch.bootout(label: job.label)
        }
        try launch.bootstrap(plist: url)
    }

    /// Stops the job, and with it everything it started, and removes the plist. Does nothing if it is not loaded.
    public func stop(label: String, stem: String) throws {
        defer { try? FileManager.default.removeItem(at: plistURL(stem: stem)) }
        if launch.isLoaded(label: label) {
            try launch.bootout(label: label)
        }
    }
}

public extension LaunchControlling {
    func info(label: String) -> JobInfo? {
        isLoaded(label: label) ? JobInfo(running: true) : nil
    }
}
