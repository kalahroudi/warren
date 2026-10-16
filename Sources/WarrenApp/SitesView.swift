// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WarrenCore

struct SitesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var runtimes: RuntimesModel
    @ObservedObject var setupRun: SetupRunModel
    let addSite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PageHeader(title: "Sites", subtitle: "Any folder, any framework, any domain you like.")
                Spacer()
                if model.snapshot.isLive {
                    Button { addSite() } label: { Label("Add site", systemImage: "plus") }
                        .keyboardShortcut("n")
                        .accessibilityLabel("Add site")
                }
            }
            HStack(alignment: .top, spacing: 16) {
                list.frame(width: 360)
                if let site = model.selectedSite {
                    detail(site)
                }
            }
        }
        .padding(24)
        .onAppear {
            runtimes.reload()
            model.selectedSiteID.map(setupRun.loadTrust)
        }
    }

    private var list: some View {
        if model.snapshot.sites.isEmpty {
            return AnyView(emptyState)
        }
        return AnyView(listContent)
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("No sites yet").font(.system(size: 14.5, weight: .semibold))
                Text(
                    "Add a project folder. Warren shows what it found and what it takes to run before it changes anything."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                if model.snapshot.isLive {
                    Button("Add site") { addSite() }
                }
            }
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.snapshot.sites) { site in
                    Button { model.selectedSiteID = site.id } label: { row(site) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ site: Site) -> some View {
        let selected = site.id == model.selectedSiteID
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.domain).font(.system(size: 14, weight: .medium))
                Text("\(site.stack) · \(site.runtime)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if site.relayURL != nil {
                Chip(text: "Relay", tint: .blue)
            }
            StatusDot(running: site.state == .running)
        }
        .padding(12)
        .background(
            selected ? Color.warrenAccent.opacity(0.1) : Color.warrenCard,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(selected ? Color.warrenAccent.opacity(0.4) : Color.warrenHairline))
    }

    private var certificateNote: String {
        let network = model.snapshot.network
        guard network.proxy.running else { return "Local · the proxy is not running" }
        switch network.rootTrusted {
        case true?: return "Local · trusted certificate"
        case false?: return "Local · certificate not trusted yet"
        case nil: return "Local · no certificate yet"
        }
    }

    private func detail(_ site: Site) -> some View {
        let running = site.state == .running
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.domain).font(.system(size: 19, weight: .semibold))
                    Text(site.path).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(running ? "Stop" : "Start") { model.setSite(site.id, running: !running) }
                    .disabled(!model.snapshot.capabilities.canControlSites)
                    .help(model.snapshot.capabilities
                        .canControlSites ? "" : "Starting and stopping sites arrives with the process manager")
            }
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Domain")
                    Text("https://\(site.domain)").font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    Text(certificateNote).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            runtimeCard(site)
            setupCard(site)
            relayCard(site)
            HStack(spacing: 10) {
                info("Framework", site.stack)
                info("Runtime", site.runtime)
                info("State", site.state.rawValue.capitalized)
            }
            if !site.startLine.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Starts with").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(site.startLine).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .background(Color.warrenCard, in: RoundedRectangle(cornerRadius: 16))
    }

    /// What is left to do for the site, and the button to do it. During and after a run it shows live progress.
    /// Hidden once complete.
    @ViewBuilder
    private func setupCard(_ site: Site) -> some View {
        if model.snapshot.isLive {
            if setupRun.isShowing(site.id) {
                runCard(site)
            } else if let plan = runtimes.setups[site.id], !plan.isComplete {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "Setup")
                            Spacer()
                            Button("Run setup") { setupRun.start(siteID: site.id) }
                                .disabled(setupRun.running || PlanRunner.selectedSteps(plan).isEmpty)
                        }
                        PlanStepList(steps: plan.steps.filter { $0.kind != .site })
                        trustLine(site)
                    }
                }
            }
        }
    }

    private func runCard(_ site: Site) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: setupRun.running ? "Setting up" : "Setup")
                    Spacer()
                    if setupRun.running {
                        Button("Stop") { setupRun.stop() }
                    } else {
                        Button("Run again") { setupRun.start(siteID: site.id) }
                    }
                }
                PlanStepList(steps: setupRun.steps, progress: setupRun.progress)
                if let summary = setupRun.summary {
                    Text(summaryText(summary)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                trustLine(site)
            }
        }
    }

    private func summaryText(_ summary: RunSummary) -> String {
        if summary.cancelled {
            return "Stopped. Run again to continue where it left off."
        }
        if summary.succeeded {
            return "Done."
        }
        if summary.failed.isEmpty {
            return "Some steps were skipped. Run again to approve them."
        }
        let count = summary.failed.count
        return "\(count) step\(count == 1 ? "" : "s") failed. Fix the cause and run again; finished steps are not repeated."
    }

    @ViewBuilder
    private func trustLine(_ site: Site) -> some View {
        if (setupRun.trusted[site.id] ?? 0) > 0 {
            HStack {
                Text("Trusted: these commands run without asking.").font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Button("Stop trusting") { setupRun.stopTrusting(site.id) }.font(.system(size: 11.5))
            }
        }
    }

    /// What the site needs from Node or Bun, and a button to install it if it is missing. Shown only when the site
    /// asks for something.
    @ViewBuilder
    private func runtimeCard(_ site: Site) -> some View {
        if model.snapshot.isLive, let plan = runtimes.plan(for: site.id), !plan.needs.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Runtime")
                    if let installing = runtimes.installing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Installing \(installing.label) · \(installing.progress)")
                                .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    ForEach(plan.needs, id: \.requirement.label) { need in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(need.requirement.label).font(.system(size: 13.5, weight: .medium))
                                Text("from \(need.requirement.source.label)")
                                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let version = need.installedVersion {
                                Chip(text: "Installed \(version)", tint: .warrenAccent)
                            } else {
                                Chip(text: "Not installed", tint: .orange)
                                Button("Install") { runtimes.install(need.requirement) }
                                    .accessibilityLabel("Install \(need.requirement.label)")
                                    .disabled(runtimes.installing != nil)
                            }
                        }
                    }
                }
            }
        }
    }

    private func relayCard(_ site: Site) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Share")
                if let url = site.relayURL {
                    HStack {
                        Text(url).font(.system(size: 13, design: .monospaced))
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        }
                    }
                } else {
                    Text("Not shared. Tailscale and Cloudflare options arrive with the sharing specs.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 13.5, weight: .medium))
            }
        }
    }
}
