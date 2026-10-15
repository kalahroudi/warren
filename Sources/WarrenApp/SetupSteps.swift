// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// What each wizard step says and does. The layout is in `SetupWizardView`.
extension SetupWizardView {
    var welcome: some View {
        page(
            title: "Let's set up Warren",
            intro: "Warren gives your local projects real https:// addresses on names you choose, like acme.test. "
                + "That takes three one-time steps.",
            body: AnyView(notes([
                "Run a small local HTTPS proxy in the background. No password needed.",
                "Trust Warren's local certificate, so browsers accept it. macOS asks for your password.",
                "Point your local domains at this Mac. macOS asks for your password once more.",
            ])),
            hint: "Nothing changes until you say so, and every step can be undone.",
            primary: StepPrimary(title: "Get started") { model.next() }
        )
    }

    var httpsStep: some View {
        let done = model.state(of: .https).isDone
        return page(
            step: .https,
            title: "Start local HTTPS",
            intro: "Warren runs Caddy, a well-known web server, as a background service. It downloads Caddy (about 50 MB, "
                + "checked against a published checksum), starts it, and keeps it running whenever you log in.",
            changes: StepChanges(
                text: "Downloads Caddy into ~/Warren/bin and adds a background service, dev.warren.proxy, "
                    + "to ~/Library/LaunchAgents.",
                detail: "No password needed."
            ),
            body: AnyView(notes([
                "Local HTTPS runs only on this Mac. Other machines on your network get nothing.",
                "Stop it any time and the service is removed.",
            ])),
            hint: done ? "Local HTTPS is running." : "This is the only step that downloads anything.",
            undo: done ? StepLink(title: "Stop and remove") { Task { await model.undoHTTPS() } } : nil,
            primary: done
                ? StepPrimary(title: "Continue") { model.next() }
                : StepPrimary(title: "Download and start") { Task { await model.startHTTPS(); advanceIfDone(.https) } }
        )
    }

    var trustStep: some View {
        let done = model.state(of: .trust).isDone
        let ready = model.state(of: .https).isDone
        return page(
            step: .trust,
            title: "Trust Warren's local certificate",
            intro: "Warren gives your sites real https:// addresses using its own local certificate authority. "
                + "To make your browsers accept it, macOS needs to trust that certificate once.",
            changes: StepChanges(
                text: "Adds Warren Local CA to your System keychain as a trusted root.",
                detail: "macOS will ask for your password. Touch ID works too."
            ),
            body: AnyView(notes([
                "The certificate's private key stays on this Mac, in a folder only your account can read.",
                "You can remove the trust any time with Undo below.",
                "Warren never trusts anything without asking, and never without showing what it will change.",
            ])),
            hint: ready ? "Without this, browsers show a security warning for your sites." : "Start local HTTPS first.",
            undo: done ? StepLink(title: "Stop trusting") { Task { await model.undoTrust() } } : nil,
            primary: done
                ? StepPrimary(title: "Continue") { model.next() }
                : StepPrimary(title: "Trust certificate…", disabled: !ready) {
                    Task { await model.trustCertificate(); advanceIfDone(.trust) }
                }
        )
    }

    var domainsStep: some View {
        let done = model.state(of: .domains).isDone
        let files = model.resolverFiles
        return page(
            step: .domains,
            title: "Point your domains at this Mac",
            intro: "Warren runs a tiny DNS server on this Mac only, and tells macOS to ask it about your local domains. "
                + "Everything else keeps using your normal DNS.",
            changes: StepChanges(
                text: files.isEmpty
                    ? "Writes one file per local domain in /etc/resolver."
                    : "Writes " + files.joined(separator: ", ") + ".",
                detail: "macOS will ask for your password."
            ),
            body: AnyView(notes([
                "Sites under .localhost need none of this. You can skip it.",
                "Only your domains go to Warren. Real websites are never touched.",
                "Adding more .test sites later needs no further password.",
            ])),
            hint: "Without this, names like acme.test will not open.",
            undo: done ? StepLink(title: "Remove") { Task { await model.undoDomains() } } : nil,
            skip: done ? nil : StepLink(title: "Skip for now") { model.skipDomains() },
            primary: done
                ? StepPrimary(title: "Continue") { model.next() }
                : StepPrimary(title: "Set up local domains…") {
                    Task { await model.enableDomains(); advanceIfDone(.domains) }
                }
        )
    }

    var checkStep: some View {
        let passed = model.state(of: .check).isDone
        let title = model.lastCheck == nil ? "Run check" : "Run again"
        return page(
            step: .check,
            title: "Check that it all works",
            intro: "Warren loads its own page, https://warren.test, the way a browser would, to prove the name resolves, "
                + "the certificate is trusted and the proxy answers.",
            body: AnyView(results),
            hint: model.lastCheck?.passed == false ? nil : "Takes a second.",
            primary: passed
                ? StepPrimary(title: "Continue") { model.next() }
                : StepPrimary(title: title) { Task { await model.runCheck() } }
        )
    }

    var doneStep: some View {
        page(
            title: "You're all set",
            intro: "Your sites can now have real https addresses on names you choose.",
            body: AnyView(VStack(alignment: .leading, spacing: 14) {
                results
                Text(
                    "Adding sites from the app arrives soon. For now, register a project with: warren site add <folder>"
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            }),
            hint: "You can run this again any time from the menu bar, under Set up Warren.",
            primary: StepPrimary(title: "Close") { onClose() }
        )
    }

    // MARK: - Pieces

    private struct ResultRow {
        let title: String
        let detail: String
        let done: Bool
    }

    var results: some View {
        let check = model.lastCheck
        let rows = [
            ResultRow(title: "Local HTTPS is running", detail: "Starts at login", done: model.state(of: .https).isDone),
            ResultRow(
                title: "Warren's certificate is trusted",
                detail: "Browsers accept https for your sites",
                done: model.state(of: .trust).isDone
            ),
            ResultRow(
                title: "Your domains point at this Mac",
                detail: "Answered by Warren's local DNS",
                done: model.state(of: .domains).isDone
            ),
            ResultRow(
                title: "https://warren.test loaded",
                detail: check?.message ?? "Not checked yet",
                done: check?.passed == true
            ),
        ]
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.done ? Color.warrenAccent : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(.system(size: 13.5, weight: .medium))
                        Text(row.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.warrenCard, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    func notes(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.warrenAccent)
                        .padding(.top, 3)
                    Text(line).font(.system(size: 13.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    func advanceIfDone(_ step: SetupStep) {
        if model.state(of: step).isDone {
            model.next()
        }
    }
}
