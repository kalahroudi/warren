// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A language runtime Warren can install. PHP and Python follow in specs 008 and 009.
public enum RuntimeKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case node
    case bun

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .node: "Node"
        case .bun: "Bun"
        }
    }

    /// Single-purpose version files a project may carry, besides `.tool-versions`.
    var versionFiles: [String] {
        switch self {
        case .node: [".nvmrc", ".node-version"]
        case .bun: [".bun-version"]
        }
    }
}

/// Where a project's version request came from.
public enum RequirementSource: Equatable, Codable, Sendable {
    case warrenConfig
    case file(String)
    case engines

    public var label: String {
        switch self {
        case .warrenConfig: ".warren.toml"
        case let .file(name): name
        case .engines: "package.json"
        }
    }
}

/// A runtime version a project asks for, as written. `22`, `22.1.0`, `lts`, `latest`, or a range for `engines`.
public struct RuntimeRequirement: Equatable, Codable, Sendable {
    public let kind: RuntimeKind
    public let requested: String
    public let source: RequirementSource

    public init(kind: RuntimeKind, requested: String, source: RequirementSource) {
        self.kind = kind
        self.requested = requested
        self.source = source
    }

    public var label: String {
        "\(kind.displayName) \(requested)"
    }
}
