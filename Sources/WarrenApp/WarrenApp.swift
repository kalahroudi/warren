// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

@main
struct WarrenApp: App {
    @StateObject private var model = AppModel(provider: FixtureProvider())

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
