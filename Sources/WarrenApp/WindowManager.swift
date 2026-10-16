// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Owns Warren's two regular windows. They are plain AppKit windows, so the menu bar popover can open them
/// without depending on SwiftUI scenes. The Dock icon shows only while one of them is open.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let setup: SetupModel
    private let runtimes: RuntimesModel
    private var mainWindow: NSWindow?
    private var setupWindow: NSWindow?

    init(model: AppModel, setup: SetupModel, runtimes: RuntimesModel) {
        self.model = model
        self.setup = setup
        self.runtimes = runtimes
    }

    func openMain() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Warren"
            window.contentViewController = NSHostingController(rootView: MainWindowView(
                model: model,
                runtimes: runtimes
            ))
            window.setContentSize(NSSize(width: 1100, height: 720))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            mainWindow = window
        }
        show(mainWindow)
    }

    func openSetup() {
        setup.restart()
        if setupWindow == nil {
            let view = SetupWizardView(model: setup) { [weak self] in self?.setupWindow?.close() }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Set up Warren"
            window.contentViewController = NSHostingController(rootView: view)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            setupWindow = window
        }
        show(setupWindow)
    }

    private func show(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === setupWindow {
            setup.stopWatching()
            setup.recordDismissal()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let open = [mainWindow, setupWindow].contains { $0?.isVisible == true }
            if !open {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
