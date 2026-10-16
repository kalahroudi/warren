// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum PlanStepKind: String, Codable, Sendable {
    case runtime, packageManager, scaffold, clone, dependencies, envFile, envValues, service, application, database,
         optional, site
}

public enum PlanStepState: Equatable, Codable, Sendable {
    case done
    case todo
    /// Cannot run yet; the text says what it is waiting for.
    case waiting(String)

    public var isDone: Bool {
        self == .done
    }
}

public struct PlanStep: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let kind: PlanStepKind
    public let title: String
    public let detail: String
    /// The command as an argument list, or nil for a step Warren performs itself.
    public let command: [String]?
    /// True when running the step executes code that came with the project (install scripts, artisan, a project's
    /// own setup script). Those need the user's approval (spec 012).
    public let runsProjectCode: Bool
    public var state: PlanStepState
    public let waitsFor: [String]
    public let enabledByDefault: Bool
    /// What a step Warren performs itself needs to know, such as the tool and version to install.
    public var payload: [String: String] = [:]

    /// What a remembered run is compared with: the command, or for the values step its fixed word and the names asked.
    var memoryCommand: [String]? {
        kind == .envValues ? ["env-values"] + (payload["names"] ?? "").split(separator: ",").map(String.init) : command
    }

    public var commandLine: String? {
        command?.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}

/// A runtime the project needs, and whether it is installed.
public struct PlannedRuntime: Equatable, Codable, Sendable {
    public let label: String
    public let source: String
    public let installedVersion: String?
    /// True when the project names no version and Warren suggests one.
    public let proposed: Bool
    public let requirement: RuntimeRequirement
}

public struct EnvSummary: Equatable, Codable, Sendable {
    /// The example file found (`.env.example`), if any.
    public let example: String?
    public let envExists: Bool
    /// Variables the example leaves empty, for a person to fill in.
    public let emptyVariables: [String]
}

/// What a project is and what it takes to run it. Built from the folder and the machine's state; running it is
/// spec 012.
public struct SetupPlan: Equatable, Codable, Sendable {
    public let siteID: String
    public let folder: String
    public let detection: FrameworkDetection
    public let runtimes: [PlannedRuntime]
    public let env: EnvSummary
    public let services: [ServiceNeed]
    public var steps: [PlanStep]

    /// Steps that are on by default and not finished.
    public var remaining: [PlanStep] {
        steps.filter { $0.enabledByDefault && !$0.state.isDone }
    }

    public var isComplete: Bool {
        remaining.isEmpty
    }
}
