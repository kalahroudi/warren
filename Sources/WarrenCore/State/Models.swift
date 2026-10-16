// SPDX-License-Identifier: Apache-2.0

public enum RunState: String, Sendable {
    case running
    case stopped
    case hibernated
}

public struct Site: Identifiable, Hashable, Sendable {
    public let id: String
    public let domain: String
    public let stack: String
    public let runtime: String
    public let detail: String
    public let path: String
    public var state: RunState
    public let relayURL: String?
    /// How the site is started or served, from framework detection. Empty when unknown.
    public var startLine = ""
}

public struct Service: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let port: Int
    public var running: Bool
    public let memoryMB: Int
}

public struct RuntimeVersion: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let note: String
    public let sizeMB: Int
    public let isDefault: Bool
    public let updateAvailable: Bool
}

public struct RuntimeGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let note: String
    public let versions: [RuntimeVersion]
}

public struct AgentClient: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let connected: Bool
}

public struct ToolPermission: Identifiable, Hashable, Sendable {
    public let id: String
    public let tool: String
    public let summary: String
    public let asksFirst: Bool
}

public struct AgentActivity: Identifiable, Hashable, Sendable {
    public let id: String
    public let time: String
    public let client: String
    public let call: String
    public let result: String
}

public struct AgentsInfo: Hashable, Sendable {
    public let endpoint: String
    public let clients: [AgentClient]
    public let permissions: [ToolPermission]
    public let activity: [AgentActivity]
}

public struct StorageCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let gigabytes: Double
}

public struct ReclaimItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let note: String
    public let gigabytes: Double
}

public struct StoragePolicy: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let value: String
}

public struct StorageInfo: Hashable, Sendable {
    public let categories: [StorageCategory]
    public let reclaim: [ReclaimItem]
    public let policies: [StoragePolicy]

    public var totalGigabytes: Double {
        categories.reduce(0) { $0 + $1.gigabytes }
    }

    public var reclaimableGigabytes: Double {
        reclaim.reduce(0) { $0 + $1.gigabytes }
    }
}

public struct UpdateInfo: Hashable, Sendable {
    public let version: String
    public let deltaMB: Int
}

public struct ServiceStatus: Equatable, Sendable {
    public var installed: Bool
    public var running: Bool
}

/// Whether Warren's local HTTPS proxy and DNS server are installed and running.
public struct NetworkStatus: Equatable, Sendable {
    public var proxy: ServiceStatus
    public var dns: ServiceStatus
    /// Whether the system trusts Warren's local certificate. Nil until the certificate exists.
    public var rootTrusted: Bool?
}

/// What the current state source can actually do, so the UI never offers a button that does nothing.
public struct Capabilities: Equatable, Sendable {
    public var canControlSites: Bool
    public var canPause: Bool
}

public struct StateSnapshot: Equatable, Sendable {
    public var sites: [Site]
    public var services: [Service]
    public var runtimeGroups: [RuntimeGroup]
    public var activeRuntimes: [String]
    public var agents: AgentsInfo
    public var storage: StorageInfo
    public var update: UpdateInfo?
    public var paused: Bool
    public var network: NetworkStatus
    public var capabilities: Capabilities
    /// True when sites and network status are real. False for demo data.
    public var isLive: Bool
    /// Local HTTPS, the certificate and local domains are all set up (see the setup wizard).
    public var setupComplete: Bool
    /// Sections that still show demo data, even in live mode. Section names match the sidebar titles.
    public var previewSections: Set<String>
    /// A short message about something that just went wrong, such as a failed resume. Nil when all is well.
    public var notice: String?

    public var runningSiteCount: Int {
        sites.filter { $0.state == .running }.count
    }

    public var runningServiceCount: Int {
        services.filter(\.running).count
    }
}
