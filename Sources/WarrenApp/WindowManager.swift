// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// Owns Warren's two regular windows. They are plain AppKit windows, so the menu bar popover can open them
/// without depending on SwiftUI scenes. The Dock icon shows only while one of them is open.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let setup: SetupModel
    private let runtimes: RuntimesModel
    private let setupRun: SetupRunModel
    private var mainWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var addSiteWindow: NSWindow?

    init(model: AppModel, setup: SetupModel, runtimes: RuntimesModel, setupRun: SetupRunModel) {
        self.model = model
        self.setup = setup
        self.runtimes = runtimes
        self.setupRun = setupRun
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
                runtimes: runtimes,
                setupRun: setupRun,
                addSite: { [weak self] in self?.openAddSite() }
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

    /// A fresh window each time, so it never shows a previous folder.
    func openAddSite() {
        addSiteWindow?.close()
        let paths = WarrenPaths.fromEnvironment()
        let model = AddSiteModel(paths: paths) { [weak self] site, runSetup in
            self?.finishAdding(site, runSetup: runSetup, template: nil)
        }
        let project = NewProjectModel(paths: paths) { [weak self] site, template in
            self?.finishAdding(site, runSetup: true, template: template)
        }
        let view = AddSiteView(model: model, project: project) { [weak self] in self?.addSiteWindow?.close() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add a site"
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        addSiteWindow = window
        show(window)
    }

    /// After a site is added or created: close the window, show the site, and optionally run its setup (for a
    /// template, the scaffolder first, then the normal plan).
    private func finishAdding(_ site: ResolvedSite, runSetup: Bool, template: ProjectTemplate?) {
        addSiteWindow?.close()
        model.refresh()
        model.section = .sites
        model.selectedSiteID = site.id
        runtimes.reload()
        // One turn later, so the Add site window has finished closing before the main window is ordered in.
        DispatchQueue.main.async {
            self.openMain()
            if runSetup {
                self.setupRun.start(siteID: site.id, template: template)
            }
        }
    }

    private func show(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // Lay out and draw now, so a window shown right after the Dock icon appears is never left empty.
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === setupWindow {
            setup.stopWatching()
            setup.recordDismissal()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let open = [mainWindow, setupWindow, addSiteWindow].contains { $0?.isVisible == true }
            if !open {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
