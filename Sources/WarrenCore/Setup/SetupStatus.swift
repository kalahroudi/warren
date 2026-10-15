// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum SetupStep: String, CaseIterable, Sendable {
    case welcome
    case https
    case trust
    case domains
    case check
    case done

    public var title: String {
        switch self {
        case .welcome: "Welcome"
        case .https: "Local HTTPS"
        case .trust: "Trust the certificate"
        case .domains: "Local domains"
        case .check: "Check"
        case .done: "Done"
        }
    }
}

public enum StepState: Equatable, Sendable {
    case done
    case pending
    /// Something is partly set up or broken. The text says what to do.
    case attention(String)

    public var isDone: Bool {
        self == .done
    }
}

/// The result of loading Warren's own check page the way a browser would.
public struct CheckResult: Equatable, Sendable {
    public let passed: Bool
    public let message: String
}

/// What the user chose not to do, remembered across launches. Everything else is derived from the machine.
public struct UserState: Codable, Equatable, Sendable {
    public var setupDismissed = false
    public var domainsSkipped = false
    /// The user paused Warren: local HTTPS and DNS stay off, including across logins, until they resume.
    public var paused = false

    public init() {}

    /// Tolerates files written by older versions that lack newer keys.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        setupDismissed = try values.decodeIfPresent(Bool.self, forKey: .setupDismissed) ?? false
        domainsSkipped = try values.decodeIfPresent(Bool.self, forKey: .domainsSkipped) ?? false
        paused = try values.decodeIfPresent(Bool.self, forKey: .paused) ?? false
    }

    public static func load(_ paths: WarrenPaths) -> UserState {
        guard let data = try? Data(contentsOf: paths.userStateFile),
              let state = try? JSONDecoder().decode(UserState.self, from: data) else { return UserState() }
        return state
    }

    public func save(_ paths: WarrenPaths) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: paths.userStateFile, options: .atomic)
    }
}

public extension WarrenPaths {
    var userStateFile: URL {
        configDirectory.appendingPathComponent("state.json")
    }
}

public struct SetupStatus: Equatable, Sendable {
    public let https: StepState
    public let trust: StepState
    public let domains: StepState
    public let check: StepState

    public func state(of step: SetupStep) -> StepState {
        switch step {
        case .welcome, .done: .done
        case .https: https
        case .trust: trust
        case .domains: domains
        case .check: check
        }
    }

    /// Everything Warren needs is in place. The check is a verification, not a requirement.
    public var isComplete: Bool {
        https.isDone && trust.isDone && domains.isDone
    }
}

/// Works out each step's state by inspecting the machine, never from remembered flags.
public struct SetupAssessor: Sendable {
    public let paths: WarrenPaths
    public let network: NetworkServices

    public init(paths: WarrenPaths, network: NetworkServices? = nil) {
        self.paths = paths
        self.network = network ?? NetworkServices(paths: paths)
    }

    public func assess(lastCheck: CheckResult? = nil) -> SetupStatus {
        assess(status: network.status(), lastCheck: lastCheck)
    }

    /// Like `assess`, for callers that already have the current network status.
    public func assess(status: NetworkStatus, lastCheck: CheckResult? = nil) -> SetupStatus {
        let settings = NetworkSettings.load(paths)
        let user = UserState.load(paths)

        // Stopped on purpose (no background job) just reads "not done yet". Attention means it should be
        // running and is not answering.
        let https: StepState = if status.proxy.running {
            .done
        } else if status.proxy.installed, network.background.isLoaded(.proxy) {
            .attention("The proxy is installed but not responding.")
        } else {
            .pending
        }

        let trust: StepState = switch status.rootTrusted {
        case true?: .done
        case false?: .pending
        case nil: .pending
        }

        let domains = domainsState(status: status, port: settings.dnsPort, skipped: user.domainsSkipped)

        let check: StepState = if let lastCheck {
            lastCheck.passed ? .done : .attention(lastCheck.message)
        } else {
            .pending
        }
        return SetupStatus(https: https, trust: trust, domains: domains, check: check)
    }

    private func domainsState(status: NetworkStatus, port: Int, skipped: Bool) -> StepState {
        if skipped {
            return .done
        }
        let resolversReady = (try? network.dns.inspectResolvers(port: port).entries
            .allSatisfy { $0.state == .current }) ?? false
        if status.dns.running, resolversReady {
            return .done
        }
        if resolversReady || network.background.isLoaded(.dns) {
            return .attention("The local DNS server is not responding.")
        }
        return .pending
    }
}
