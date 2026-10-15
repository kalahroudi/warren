// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WarrenCore

struct SitesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Sites", subtitle: "Any folder, any framework, any domain you like.")
            HStack(alignment: .top, spacing: 16) {
                list.frame(width: 360)
                if let site = model.selectedSite {
                    detail(site)
                }
            }
        }
        .padding(24)
    }

    private var list: some View {
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
            }
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Domain")
                    Text("https://\(site.domain)").font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    Text("Local · trusted certificate").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            relayCard(site)
            HStack(spacing: 10) {
                info("Framework", site.stack)
                info("Runtime", site.runtime)
                info("State", site.state.rawValue.capitalized)
            }
            Spacer()
        }
        .padding(20)
        .background(Color.warrenCard, in: RoundedRectangle(cornerRadius: 16))
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
