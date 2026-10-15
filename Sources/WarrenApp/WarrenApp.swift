// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

@main
struct WarrenApp: App {
    @StateObject private var model = AppModel(provider: Self.makeProvider())

    /// Real state by default. `WARREN_DEMO=1` shows the demo data instead, for screenshots and design work.
    private static func makeProvider() -> any StateProvider {
        ProcessInfo.processInfo.environment["WARREN_DEMO"] == "1"
            ? FixtureProvider()
            : LiveProvider(paths: .fromEnvironment())
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.make())
        }
        .menuBarExtraStyle(.window)

        Window("Warren", id: MainWindow.id) {
            MainWindowView(model: model)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
