// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A language runtime Warren can install. Deno and others can follow.
public enum RuntimeKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case node
    case bun
    case php
    case python

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .node: "Node"
        case .bun: "Bun"
        case .php: "PHP"
        case .python: "Python"
        }
    }

    /// Single-purpose version files a project may carry, besides `.tool-versions`.
    var versionFiles: [String] {
        switch self {
        case .node: [".nvmrc", ".node-version"]
        case .bun: [".bun-version"]
        case .php: [".php-version"]
        case .python: [".python-version"]
        }
    }
}

/// Where a project's version request came from.
public enum RequirementSource: Equatable, Codable, Sendable {
    case warrenConfig
    case file(String)
    case engines
    case composer
    case pyproject

    public var label: String {
        switch self {
        case .warrenConfig: ".warren.toml"
        case let .file(name): name
        case .engines: "package.json"
        case .composer: "composer.json"
        case .pyproject: "pyproject.toml"
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

    /// The range this requirement asks for, when it came from `package.json`, `composer.json` or `pyproject.toml`.
    var range: VersionRange? {
        switch source {
        case .engines: VersionRange(requested)
        case .composer: VersionRange(composer: requested)
        case .pyproject: VersionRange(pep440: requested)
        default: nil
        }
    }
}
