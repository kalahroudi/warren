// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// Placeholder shell until spec 002.
@main
struct WarrenApp: App {
    var body: some Scene {
        MenuBarExtra("Warren", systemImage: "door.left.hand.closed") {
            Text("Warren \(Warren.version)")
            Divider()
            Button("Quit Warren") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
