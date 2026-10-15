// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct SetupTests {
    private let root: URL
    private let paths: WarrenPaths
    private let launch = FakeLaunch()

    init() throws {
        root = try temporaryDirectory("setup")
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
    }

    private func network(resolvers: URL? = nil) -> NetworkServices {
        NetworkServices(
            paths: paths,
            background: BackgroundServices(
                paths: paths,
                agentsDirectory: root.appendingPathComponent("agents"),
                launch: launch
            ),
            resolvers: ResolverManager(directory: resolvers ?? root.appendingPathComponent("resolver"))
        )
    }

    private func writeRootCertificate(der: String = "hello") throws {
        let certificate = paths.caddyRootCertificate
        try FileManager.default.createDirectory(
            at: certificate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let pem = "-----BEGIN CERTIFICATE-----\n\(Data(der.utf8).base64EncodedString())\n-----END CERTIFICATE-----\n"
        try pem.write(to: certificate, atomically: true, encoding: .utf8)
    }

    // MARK: Assessment

    @Test func aFreshMachineHasNothingDone() {
        let status = SetupAssessor(paths: paths, network: network()).assess()
        #expect(status.https == .pending)
        #expect(status.trust == .pending)
        #expect(status.domains == .pending)
        #expect(status.check == .pending)
        #expect(!status.isComplete)
    }

    @Test func skippingDomainsCountsAsDone() throws {
        var user = UserState()
        user.domainsSkipped = true
        try user.save(paths)
        #expect(SetupAssessor(paths: paths, network: network()).assess().domains == .done)
    }

    @Test func theCheckStepFollowsTheLastResult() {
        let assessor = SetupAssessor(paths: paths, network: network())
        #expect(assessor.assess(lastCheck: CheckResult(passed: true, message: "ok")).check == .done)
        let failed = assessor.assess(lastCheck: CheckResult(passed: false, message: "no certificate"))
        #expect(failed.check == .attention("no certificate"))
    }

    @Test func theCheckDoesNotCountTowardsCompletion() {
        let status = SetupStatus(https: .done, trust: .done, domains: .done, check: .pending)
        #expect(status.isComplete)
        #expect(!SetupStatus(https: .done, trust: .pending, domains: .done, check: .done).isComplete)
    }

    @Test func welcomeAndDoneAreNeverGatedOnTheMachine() {
        let status = SetupStatus(https: .pending, trust: .pending, domains: .pending, check: .pending)
        #expect(status.state(of: .welcome).isDone)
        #expect(status.state(of: .done).isDone)
        #expect(!status.state(of: .trust).isDone)
    }

    @Test func userStateRoundTripsAndFallsBackToDefaults() throws {
        #expect(UserState.load(paths) == UserState())
        var state = UserState()
        state.setupDismissed = true
        try state.save(paths)
        #expect(UserState.load(paths).setupDismissed)
        try Data("nope".utf8).write(to: paths.userStateFile)
        #expect(UserState.load(paths) == UserState())
    }

    // MARK: Trust

    @Test func trustUsesTheSecurityToolAndTheRootCertificate() throws {
        try writeRootCertificate()
        let script = try TrustManager(paths: paths).trustScript()
        #expect(script
            .contains("/usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain"))
        #expect(script.contains(paths.caddyRootCertificate.path))
        #expect(!script.contains("sudo"))
    }

    @Test func untrustRemovesTheTrustAndTheCertificateByFingerprint() throws {
        try writeRootCertificate(der: "hello")
        let script = try TrustManager(paths: paths).untrustScript()
        #expect(script.contains("remove-trusted-cert -d"))
        #expect(script.contains("delete-certificate -Z AAF4C61DDCC5E8A2DABEDE0F3B482CD9AEA9434D"))
    }

    @Test func trustNeedsTheCertificateToExist() {
        #expect(throws: ProxyError.rootCertificateMissing) { try TrustManager(paths: paths).trustScript() }
        #expect(throws: ProxyError.rootCertificateMissing) { try TrustManager(paths: paths).untrustScript() }
    }

    // MARK: Admin dialog

    @Test func appleScriptEscapingHandlesQuotesAndBackslashes() {
        #expect(AdminRunner.escape(#"a"b\c"#) == #"a\"b\\c"#)
    }

    @Test func theAdminScriptNamesTheDialogPrompt() {
        let file = URL(fileURLWithPath: "/tmp/x.sh")
        let script = AdminRunner.appleScript(running: file, prompt: "Warren wants \"access\"", privileged: true)
        #expect(script.contains("with administrator privileges"))
        #expect(script.contains(#"with prompt "Warren wants \"access\"""#))
        #expect(!AdminRunner.appleScript(running: file, prompt: "x", privileged: false).contains("administrator"))
    }

    @Test func anUnprivilegedScriptRunsAndReturnsItsOutput() throws {
        let output = try AdminRunner.run(script: "#!/bin/sh\necho hello warren\n", prompt: "test", privileged: false)
        #expect(output == "hello warren")
    }

    @Test func aFailingScriptReportsTheFailure() {
        #expect(throws: AdminError.self) {
            try AdminRunner.run(script: "#!/bin/sh\nexit 3\n", prompt: "test", privileged: false)
        }
    }

    // MARK: Check page and reserved name

    @Test func theCheckPageIsServedAndAlwaysGetsACertificate() throws {
        let short = WarrenPaths(root: URL(fileURLWithPath: "/tmp/wh"))
        let plan = try CaddyConfig.plan(sites: [], ports: ProxyPorts(), paths: short)
        #expect(plan.configJSON.contains("warren.test"))
        #expect(plan.configJSON.contains(CaddyConfig.selfCheckBody))
        #expect(plan.configJSON.contains("\"tls\""))
    }

    @Test func warrenTestCannotBeClaimedBySite() throws {
        let folder = root.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "domains = [\"warren.test\"]".write(
            to: folder.appendingPathComponent(".warren.toml"),
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: RegistryError.domainConflict(domain: "warren.test", otherSite: "Warren (reserved)")) {
            try SiteRegistry(paths: paths).add(path: folder.path)
        }
    }

    @Test func theTestZoneAlwaysExistsBecauseOfTheCheckPage() throws {
        let plan = try network().dns.plan(port: 5354)
        #expect(plan.zones == ["test"])
    }

    @Test func checkFailuresPointAtTheStepToRedo() {
        #expect(SetupCheck.describe(URLError(.serverCertificateUntrusted)).contains("Trust"))
        #expect(SetupCheck.describe(URLError(.cannotConnectToHost)).contains("proxy"))
        #expect(SetupCheck.describe(URLError(.badURL)).contains("failed"))
    }

    @Test func portsCanBeOverriddenFromTheEnvironment() {
        let settings = NetworkSettings.defaults([
            "WARREN_HTTP_PORT": "18080",
            "WARREN_HTTPS_PORT": "18443",
            "WARREN_DNS_PORT": "15354"
        ])
        #expect(settings == NetworkSettings(httpPort: 18080, httpsPort: 18443, dnsPort: 15354))
        #expect(NetworkSettings.defaults([:]) == NetworkSettings())
    }
}
