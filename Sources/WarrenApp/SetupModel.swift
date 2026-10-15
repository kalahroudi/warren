// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// Drives the setup wizard. Every action calls the same core code as the CLI, and every step's state is
/// read back from the machine after it runs.
@MainActor
final class SetupModel: ObservableObject {
    @Published var current: SetupStep = .welcome
    @Published private(set) var status: SetupStatus
    @Published private(set) var busy: String?
    @Published var message: String?
    @Published private(set) var lastCheck: CheckResult?

    private let paths: WarrenPaths
    private let network: NetworkServices
    private let assessor: SetupAssessor
    private var watcher: Timer?

    init(paths: WarrenPaths = .fromEnvironment()) {
        self.paths = paths
        let network = NetworkServices(paths: paths)
        self.network = network
        assessor = SetupAssessor(paths: paths, network: network)
        status = assessor.assess()
        current = firstUnfinished()
    }

    var steps: [SetupStep] {
        SetupStep.allCases
    }

    func state(of step: SetupStep) -> StepState {
        status.state(of: step)
    }

    var settings: NetworkSettings {
        NetworkSettings.load(paths)
    }

    /// The resolver files the domains step would write, for showing before the password dialog.
    var resolverFiles: [String] {
        let entries = try? network.dns.inspectResolvers(port: settings.dnsPort).entries
        return (entries ?? []).map(\.path)
    }

    func refresh() {
        status = assessor.assess(lastCheck: lastCheck)
    }

    func go(to step: SetupStep) {
        message = nil
        current = step
    }

    func next() {
        guard let index = steps.firstIndex(of: current), index + 1 < steps.count else { return }
        go(to: steps[index + 1])
    }

    func back() {
        guard let index = steps.firstIndex(of: current), index > 0 else { return }
        go(to: steps[index - 1])
    }

    /// Called whenever the wizard window opens: re-reads the machine and lands on the first unfinished step.
    func restart() {
        refresh()
        current = firstUnfinished()
        startWatching()
    }

    var isWatching: Bool {
        watcher != nil
    }

    /// While the wizard is open, keep each step's state in step with the machine.
    func startWatching() {
        watcher?.invalidate()
        watcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.busy == nil else { return }
                self.refresh()
            }
        }
    }

    func stopWatching() {
        watcher?.invalidate()
        watcher = nil
    }

    private func firstUnfinished() -> SetupStep {
        let status = assessor.assess()
        for step in [SetupStep.https, .trust, .domains] where !status.state(of: step).isDone {
            return step == .https ? .welcome : step
        }
        return .check
    }

    // MARK: - Actions

    func startHTTPS() async {
        await work("Downloading Caddy and starting local HTTPS…") { [paths, network] in
            let proxy = network.proxy
            if !proxy.isInstalled {
                try await proxy.install()
            }
            try network.startProxy(ports: NetworkSettings.load(paths).proxyPorts)
            // Wait until the proxy answers and has created its certificate authority.
            try await Self
                .wait(seconds: 15) {
                    proxy.isRunning() && FileManager.default.fileExists(atPath: paths.caddyRootCertificate.path)
                }
        }
    }

    func trustCertificate() async {
        await work("Waiting for your password…") { [paths] in
            let script = try TrustManager(paths: paths).trustScript()
            try await Self.admin(
                script,
                prompt: "Warren wants to trust its local certificate so browsers accept your sites."
            )
        }
    }

    func enableDomains() async {
        await work("Setting up local domains…") { [paths, network] in
            let port = NetworkSettings.load(paths).dnsPort
            if !network.dns.isInstalled {
                try await network.dns.install()
            }
            try network.startDNS(port: port)
            try await Self.wait(seconds: 15) { PortCheck.isListening(port) }
            let entries = try network.dns.inspectResolvers(port: port).entries
            if let script = try network.dns.resolvers.installScript(entries: entries, port: port) {
                let privileged = network.dns.resolvers.needsPrivilege
                try await Self.admin(
                    script,
                    prompt: "Warren wants to point your local domains at this Mac.",
                    privileged: privileged
                )
            }
        }
    }

    func skipDomains() {
        var user = UserState.load(paths)
        user.domainsSkipped = true
        try? user.save(paths)
        refresh()
        next()
    }

    func runCheck() async {
        busy = "Checking…"
        message = nil
        lastCheck = await SetupCheck.run(httpsPort: settings.httpsPort)
        busy = nil
        refresh()
    }

    func undoHTTPS() async {
        await work("Stopping local HTTPS…") { [network] in try network.stop(.proxy) }
    }

    func undoTrust() async {
        await work("Waiting for your password…") { [paths] in
            let script = try TrustManager(paths: paths).untrustScript()
            try await Self.admin(script, prompt: "Warren wants to stop trusting its local certificate.")
        }
    }

    func undoDomains() async {
        await work("Removing local domains…") { [paths, network] in
            if let script = network.dns.resolvers.removalScript() {
                try await Self.admin(
                    script, prompt: "Warren wants to remove its local domain settings.",
                    privileged: network.dns.resolvers.needsPrivilege
                )
            }
            try network.stop(.dns)
            var user = UserState.load(paths)
            user.domainsSkipped = false
            try user.save(paths)
        }
    }

    /// Remembers that the user closed the wizard before finishing, so it does not reopen by itself every launch.
    func recordDismissal() {
        guard !status.isComplete else { return }
        var user = UserState.load(paths)
        user.setupDismissed = true
        try? user.save(paths)
    }

    // MARK: - Plumbing

    private func work(_ label: String, _ action: @escaping @Sendable () async throws -> Void) async {
        busy = label
        message = nil
        do {
            try await action()
        } catch let error as AdminError where error == .cancelled {
            message = "Cancelled. Nothing was changed."
        } catch {
            message = error.localizedDescription
        }
        busy = nil
        refresh()
    }

    /// Waits until the condition holds, so a step is only reported done once the service is really up.
    private nonisolated static func wait(seconds: Int, until condition: @Sendable () -> Bool) async throws {
        for _ in 0 ..< seconds * 4 where !condition() {
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Runs the privileged script off the main thread, because the password dialog blocks until it is answered.
    private nonisolated static func admin(_ script: String, prompt: String, privileged: Bool = true) async throws {
        try await Task.detached {
            try AdminRunner.run(script: script, prompt: prompt, privileged: privileged)
        }.value
    }
}
