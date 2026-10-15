// SPDX-License-Identifier: Apache-2.0

import AppKit

// Everything visible is owned by AppDelegate: the menu bar item, its popover, and the windows.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
