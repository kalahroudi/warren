// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// The menu bar popover: what people look at many times a day. Setup lives in the setup wizard, not here.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    let openMain: () -> Void
    let openSetup: () -> Void
    let close: () -> Void

    private var snapshot: StateSnapshot {
        model.snapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sites
            if !snapshot.isLive {
                Divider().padding(.horizontal, 16)
                services
                if !snapshot.activeRuntimes.isEmpty {
                    Divider().padding(.horizontal, 16)
                    runtimes
                }
            }
            if let update = snapshot.update {
                updateBanner(update)
            }
            footer
        }
        .frame(width: 392)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand { close() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            AppMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("Warren").font(.system(size: 14, weight: .semibold))
                Text(statusLine).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if snapshot.capabilities.canPause {
                Button { model.togglePaused() } label: {
                    Image(systemName: snapshot.paused ? "play.fill" : "pause.fill").frame(width: 16, height: 16)
                }
                .help(snapshot.paused ? "Resume local HTTPS and DNS" : "Pause local HTTPS and DNS")
            }
            Menu {
                Button("Open Warren") { openMain() }
                Button("Set up Warren…") { openSetup() }
                Divider()
                Button("Quit Warren") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape").frame(width: 16, height: 16)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var statusLine: String {
        if snapshot.paused {
            return "Paused"
        }
        if snapshot.isLive {
            let running = snapshot.runningSiteCount
            return snapshot.sites.isEmpty ? "No sites yet" : "\(running) of \(snapshot.sites.count) running"
        }
        return "\(snapshot.runningSiteCount) sites · \(snapshot.runningServiceCount) services running"
    }

    // MARK: - Sites

    private var sites: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Sites")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            if snapshot.sites.isEmpty {
                Text("Your sites will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(snapshot.sites.prefix(6)) { site in
                Button { open(site) } label: { row(site) }
                    .buttonStyle(.plain)
                    .help(snapshot.isLive ? "Open \(site.domain)" : "")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func row(_ site: Site) -> some View {
        HStack(spacing: 10) {
            StatusDot(running: site.state == .running)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(site.domain).font(.system(size: 13, weight: .medium))
                    if site.stack != "Unknown" {
                        Chip(text: site.stack)
                    }
                }
                Text(detail(site))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if site.relayURL != nil {
                Chip(text: "Relay on", tint: .blue)
            }
        }
        .padding(8)
        .contentShape(Rectangle())
    }

    private func detail(_ site: Site) -> String {
        site.runtime == "No runtime" ? site.detail : "\(site.detail) · \(site.runtime)"
    }

    /// Opens the site in the browser. Until setup is finished its address would not work, so the wizard opens instead.
    private func open(_ site: Site) {
        guard snapshot.isLive, !snapshot.paused else { return }
        guard snapshot.setupComplete else {
            openSetup()
            return
        }
        let port = NetworkSettings.load(.fromEnvironment()).httpsPort
        let suffix = port == 443 ? "" : ":\(port)"
        if let url = URL(string: "https://\(site.domain)\(suffix)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Demo-only sections

    private var services: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Services")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(snapshot.services.prefix(4)) { service in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(service.name).font(.system(size: 12.5, weight: .medium))
                            Text(verbatim: ":" + String(service.port)).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ServiceToggle(isOn: service.running) { model.setService(service.id, running: $0) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.warrenCard, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var runtimes: some View {
        HStack(spacing: 6) {
            SectionLabel(text: "Active")
            ForEach(snapshot.activeRuntimes, id: \.self) { Chip(text: $0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private func updateBanner(_ update: UpdateInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Warren \(update.version) is ready").font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.orange)
                Text("\(update.deltaMB) MB delta · restarts in seconds")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Update") { model.applyUpdate() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// Something that was working and stopped. Setup that was never done is not mentioned here.
    private var footerProblem: String? {
        if let notice = snapshot.notice {
            return notice
        }
        guard snapshot.isLive, snapshot.setupComplete, !snapshot.paused else { return nil }
        if !snapshot.network.proxy.running {
            return "Local HTTPS stopped"
        }
        if !snapshot.network.dns.running {
            return "Local DNS stopped"
        }
        return nil
    }

    private var footer: some View {
        HStack {
            if let problem = footerProblem {
                StatusDot(running: false)
                Text(problem).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Warren ⌘O") { openMain() }
                .buttonStyle(.plain)
                .keyboardShortcut("o")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
    }
}
