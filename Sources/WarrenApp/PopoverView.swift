// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            sites
            Divider().padding(.horizontal, 16)
            services
            Divider().padding(.horizontal, 16)
            runtimes
            if let update = model.snapshot.update {
                updateBanner(update)
            }
            footer
        }
        .frame(width: 392)
        .onExitCommand { NSApp.keyWindow?.close() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("Warren").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    StatusDot(running: !model.snapshot.paused)
                    Text(statusLine).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { model.togglePaused() } label: {
                Image(systemName: model.snapshot.paused ? "play.fill" : "pause.fill")
            }
            .help(model.snapshot.paused ? "Resume everything" : "Pause everything")
            Menu {
                Button("Open Warren") { MainWindow.open(openWindow) }
                Divider()
                Button("Quit Warren") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuIndicator(.hidden)
            .help("Settings")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var statusLine: String {
        let snapshot = model.snapshot
        if snapshot.paused {
            return "Paused"
        }
        return "\(snapshot.runningSiteCount) sites · \(snapshot.runningServiceCount) services running"
    }

    private var sites: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionLabel(text: "Sites")
                Spacer()
                Text("+ New site").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.warrenAccent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            ForEach(model.snapshot.sites.prefix(4)) { site in
                HStack(spacing: 10) {
                    StatusDot(running: site.state == .running)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 7) {
                            Text(site.domain).font(.system(size: 13, weight: .medium))
                            Chip(text: site.stack)
                        }
                        Text("\(site.detail) · \(site.runtime)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if site.relayURL != nil {
                        Chip(text: "Relay on", tint: .blue)
                    }
                }
                .padding(8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var services: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Services")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(model.snapshot.services.prefix(4)) { service in
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
            ForEach(model.snapshot.activeRuntimes, id: \.self) { Chip(text: $0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

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

    private var footer: some View {
        HStack {
            StatusDot(running: true)
            Text("Claude Code connected via MCP").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button("Open Warren ⌘O") { MainWindow.open(openWindow) }
                .buttonStyle(.plain)
                .keyboardShortcut("o")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
    }
}
