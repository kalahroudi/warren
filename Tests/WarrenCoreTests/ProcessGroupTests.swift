// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing
@testable import WarrenCore

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var all: [String] {
        lock.withLock { stored }
    }

    func add(_ line: String) {
        lock.withLock { stored.append(line) }
    }
}

/// Real processes, no network: shell one-liners.
struct ProcessGroupTests {
    private let directory: URL
    private let executor = ProcessGroupExecutor()
    private let environment = ["PATH": "/usr/bin:/bin", "WARREN_TEST": "yes"]

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("wpg-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func run(_ script: String) async throws -> (Int32, [String]) {
        let lines = Lines()
        let code = try await executor.run(
            ["/bin/sh", "-c", script], directory: directory, environment: environment, onLine: lines.add
        )
        return (code, lines.all)
    }

    @Test func aCommandRunsInTheFolderWithTheGivenEnvironmentAndOutputArrivesByLine() async throws {
        let (code, lines) = try await run("pwd; echo $WARREN_TEST; echo $HOME-unset; printf 'a\\nb\\n'")
        #expect(code == 0)
        #expect(lines[0].hasSuffix(directory.lastPathComponent))
        #expect(lines.dropFirst() == ["yes", "-unset", "a", "b"])
    }

    @Test func standardInputIsClosedSoQuestionsFailInsteadOfHanging() async throws {
        let (code, lines) = try await run("read answer || exit 1; echo got-[$answer]")
        #expect(code == 1 && lines.isEmpty)
        let (cat, _) = try await run("cat; echo done")
        #expect(cat == 0)
    }

    @Test func theExitCodeIsReturned() async throws {
        #expect(try await run("exit 7").0 == 7)
        #expect(try await run("kill -9 $$").0 == 137)
    }

    @Test func aCommandFoundOnThePATHRunsAndAMissingOneIsAClearError() async throws {
        let lines = Lines()
        let code = try await executor.run(
            ["echo", "hi"],
            directory: directory,
            environment: environment,
            onLine: lines.add
        )
        #expect(code == 0 && lines.all == ["hi"])
        await #expect(throws: ProcessError.notFound("no-such-tool")) {
            try await executor.run(["no-such-tool"], directory: directory, environment: environment, onLine: { _ in })
        }
    }

    @Test func aBackgroundProcessDoesNotHoldTheStepOpenOnceTheCommandHasExited() async throws {
        let started = Date()
        let (code, lines) = try await run("(sleep 30 >/dev/null 2>&1 &) ; echo finished")
        #expect(code == 0 && lines == ["finished"])
        #expect(Date().timeIntervalSince(started) < 10)
        _ = try? await run("pkill -f 'sleep 30' || true")
    }

    @Test func stoppingEndsTheCommandAndTheProcessesItStarted() async throws {
        let pidFile = directory.appendingPathComponent("child.pid")
        let task = Task {
            try await executor.run(
                ["/bin/sh", "-c", "sleep 60 & echo $! > '\(pidFile.path)'; wait"],
                directory: directory, environment: environment, onLine: { _ in }
            )
        }
        for _ in 0 ..< 50 where !FileManager.default.fileExists(atPath: pidFile.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        let child =
            try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(child, 0) == 0)
        task.cancel()
        let code = try await task.value
        #expect(code == 143)
        var alive = true
        for _ in 0 ..< 40 where alive {
            try await Task.sleep(for: .milliseconds(50))
            alive = kill(child, 0) == 0
        }
        #expect(!alive)
    }
}
