// SPDX-License-Identifier: Apache-2.0

import Foundation
import WarrenCore

let setupUsage = """
usage: warren setup status

  status    show each setup step's state, read from this machine (the same states the app's wizard shows)
"""

func runSetup(_ arguments: [String], paths: WarrenPaths) throws {
    guard arguments.first == "status" else { throw CLIError("unknown or incomplete command\n\n\(setupUsage)") }
    let status = SetupAssessor(paths: paths).assess()
    for step in [SetupStep.https, .trust, .domains] {
        switch status.state(of: step) {
        case .done: print("\(step.title): done")
        case .pending: print("\(step.title): not done yet")
        case let .attention(text): print("\(step.title): needs attention (\(text))")
        }
    }
    print("setup complete: \(status.isComplete ? "yes" : "no")")
}
