// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// The menu bar item and its popover. The popover is anchored to the icon with an arrow and closes when you
/// click elsewhere. Right-clicking the icon shows Open, Set up and Quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppDelegate.makeModel()
    private let setup = SetupModel()
    private let runtimes = RuntimesModel(
        paths: .fromEnvironment(),
        enabled: ProcessInfo.processInfo.environment["WARREN_DEMO"] != "1"
    )
    private lazy var setupRun = SetupRunModel(
        paths: .fromEnvironment(),
        enabled: ProcessInfo.processInfo.environment["WARREN_DEMO"] != "1"
    ) { [weak self] in
        self?.runtimes.reload()
        self?.model.refresh()
    }

    private lazy var windows = WindowManager(model: model, setup: setup, runtimes: runtimes, setupRun: setupRun)
    private var item: NSStatusItem!
    private let popover = NSPopover()

    /// Real state by default. `WARREN_DEMO=1` shows the demo data instead, for screenshots and design work.
    private static func makeModel() -> AppModel {
        let demo = ProcessInfo.processInfo.environment["WARREN_DEMO"] == "1"
        return AppModel(provider: demo ? FixtureProvider() : LiveProvider(paths: .fromEnvironment()))
    }

    func applicationDidFinishLaunching(_: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = MenuBarIcon.make()
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Warren")
            button.toolTip = "Warren"
        }
        let view = PopoverView(
            model: model,
            openMain: { [weak self] in self?.open { $0.openMain() } },
            openSetup: { [weak self] in self?.open { $0.openSetup() } },
            close: { [weak self] in self?.popover.performClose(nil) }
        )
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.openSetupIfNeeded() }
    }

    /// On first launch, and until the user closes it unfinished, the wizard opens by itself.
    private func openSetupIfNeeded() {
        let snapshot = model.snapshot
        guard snapshot.isLive, !snapshot.setupComplete,
              !UserState.load(.fromEnvironment()).setupDismissed else { return }
        windows.openSetup()
    }

    private func open(_ action: (WindowManager) -> Void) {
        popover.performClose(nil)
        action(windows)
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = item.button else { return }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Warren", action: #selector(openMain), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Add site…", action: #selector(openAddSite), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Set up Warren…", action: #selector(openSetup), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Warren", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openMain() {
        windows.openMain()
    }

    @objc private func openAddSite() {
        windows.openAddSite()
    }

    @objc private func openSetup() {
        windows.openSetup()
    }
}
