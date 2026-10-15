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
        .fixedSize(horizontal: false, vertical: true)
        .background(PanelFitter(layoutKey: layoutKey))
        .onExitCommand { NSApp.keyWindow?.close() }
    }

    /// Changes whenever something that affects the popover's height changes.
    private var layoutKey: String {
        let snapshot = model.snapshot
        return "\(snapshot.sites.count)-\(snapshot.services.count)-\(snapshot.update != nil)-\(snapshot.paused)"
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
                Image(systemName: model.snapshot.paused ? "play.fill" : "pause.fill").frame(width: 16, height: 16)
            }
            .help(model.snapshot.paused ? "Resume everything" : "Pause everything")
            Menu {
                Button("Open Warren") { MainWindow.open(openWindow) }
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

/// The menu bar panel keeps its opening height when the content shrinks or grows, which leaves empty bands
/// above and below. This resizes the panel to fit its content and keeps the top edge under the menu bar.
private struct PanelFitter: NSViewRepresentable {
    /// Gives SwiftUI a reason to call `updateNSView` when the content's height may have changed.
    let layoutKey: String

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, let content = window.contentView else { return }
            let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize)).size
            guard abs(window.frame.height - target.height) > 0.5 else { return }
            var frame = window.frame
            frame.origin.y += frame.height - target.height
            frame.size.height = target.height
            window.setFrame(frame, display: true)
        }
    }
}
