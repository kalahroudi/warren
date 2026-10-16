// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

/// Runs a command as an argument list in its own process group, so stopping it also stops what it started.
/// Standard input is closed, output is read a line at a time, and nothing goes through a shell.
public protocol CommandExecuting: Sendable {
    /// Returns the exit status. Cancelling the task stops the command (SIGTERM, then SIGKILL after five seconds).
    func run(
        _ command: [String], directory: URL, environment: [String: String], onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32
}

public enum ProcessError: Error, Equatable, LocalizedError, Sendable {
    case notFound(String)
    case spawnFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case let .notFound(name): "'\(name)' was not found"
        case let .spawnFailed(code): "could not start the command (error \(code))"
        }
    }
}

public struct ProcessGroupExecutor: CommandExecuting {
    public init() {}

    public func run(
        _ command: [String], directory: URL, environment: [String: String], onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        guard let name = command.first else { throw ProcessError.notFound("") }
        let executable = try Self.resolve(name, path: environment["PATH"] ?? "/usr/bin:/bin")
        let child = try Self.spawn(executable, command, directory: directory, environment: environment)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(returning: Self.drain(child, onLine: onLine))
                }
            }
        } onCancel: {
            Self.stop(child.pid)
        }
    }

    // MARK: Finding and starting

    static func resolve(_ name: String, path: String) throws -> String {
        if name.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: name) else { throw ProcessError.notFound(name) }
            return name
        }
        for folder in path.split(separator: ":") {
            let candidate = "\(folder)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw ProcessError.notFound(name)
    }

    private struct Child {
        let pid: pid_t
        let output: Int32
    }

    private static func spawn(
        _ executable: String, _ command: [String], directory: URL, environment: [String: String]
    ) throws -> Child {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw ProcessError.spawnFailed(errno) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // A new group, with every signal back to its default and none blocked: a parent that ignores SIGTERM or
        // SIGPIPE would otherwise pass that on to the command.
        var defaults = sigset_t()
        sigfillset(&defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        )
        posix_spawnattr_setpgroup(&attributes, 0)

        let arguments = command.map { strdup($0) } + [nil]
        let variables = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            arguments.forEach { free($0) }
            variables.forEach { free($0) }
        }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, arguments, variables)
        close(fds[1])
        guard status == 0 else {
            close(fds[0])
            throw ProcessError.spawnFailed(status)
        }
        return Child(pid: pid, output: fds[0])
    }

    // MARK: Reading and stopping

    /// Reads output until the command exits, then returns its status. Output is polled rather than read to its end,
    /// because a background process the command left behind would keep the pipe open.
    private static func drain(_ child: Child, onLine: @Sendable (String) -> Void) -> Int32 {
        defer { close(child.output) }
        var pending = Data()
        var status: Int32 = 0
        var exited = false
        func flush(final: Bool) {
            let text = String(bytes: pending, encoding: .utf8) ?? ""
            var parts = text.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            let tail = parts.removeLast()
            parts.filter { !$0.isEmpty }.forEach(onLine)
            pending = final ? Data() : Data(tail.utf8)
            if final, !tail.isEmpty {
                onLine(tail)
            }
        }
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            var descriptor = pollfd(fd: child.output, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, exited ? 0 : 100)
            if ready > 0 {
                let count = read(child.output, &buffer, buffer.count)
                if count > 0 {
                    pending.append(buffer, count: count)
                    flush(final: false)
                    continue
                }
                if count == 0 {
                    break
                }
            }
            if exited {
                break
            }
            var wait: Int32 = 0
            if waitpid(child.pid, &wait, WNOHANG) == child.pid {
                exited = true
                status = wait
            }
        }
        if !exited {
            var wait: Int32 = 0
            waitpid(child.pid, &wait, 0)
            status = wait
        }
        flush(final: true)
        // The shell's own status: exit code, or 128 plus the signal that ended it.
        if status & 0x7F == 0 {
            return (status >> 8) & 0xFF
        }
        return 128 + (status & 0x7F)
    }

    /// SIGTERM to the whole group, then SIGKILL after five seconds if anything is left.
    private static func stop(_ pid: pid_t) {
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            kill(-pid, SIGKILL)
        }
    }
}
