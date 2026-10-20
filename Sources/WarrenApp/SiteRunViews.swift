// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WarrenCore

/// Starting, stopping and the log, on the site page.
extension SitesView {
    func controls(_ site: Site) -> some View {
        let busy = siteRun.busy.contains(site.id)
        let active = site.state == .running || site.state == .starting
        return HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small)
            }
            if site.state == .running {
                Button("Open") { NSWorkspace.shared.open(siteURL(site)) }
            }
            if site.state == .running, site.managed {
                Button("Restart") { siteRun.restart(site.id) }.disabled(busy)
            }
            if active, site.managed {
                Button("Stop") { siteRun.stop(site.id) }.disabled(busy && site.state != .starting)
            } else if !active {
                Button("Start") { siteRun.start(site.id) }
                    .disabled(busy || !model.snapshot.capabilities.canControlSites)
            }
        }
    }

    func siteURL(_ site: Site) -> URL {
        let port = NetworkSettings.load(.fromEnvironment()).httpsPort
        return URL(string: "https://\(site.domain)\(port == 443 ? "" : ":\(port)")") ?? URL(fileURLWithPath: "/")
    }

    /// Why a site is not up: a failed start, or a server that stopped on its own.
    @ViewBuilder
    func runStatusCard(_ site: Site) -> some View {
        if siteRun.busy.contains(site.id) || site.state == .starting {
            Text("Starting. The first request can take a moment while the site compiles.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        } else if let failure = siteRun.failures[site.id] {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Could not start")
                    Text(failure).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if site.state == .crashed {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Stopped unexpectedly")
                    Text(crashText(site)).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if site.state == .running, !site.managed {
            Text("This server was started outside Warren, so Warren cannot stop it.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    func crashText(_ site: Site) -> String {
        let cause = SiteProcesses.cause(forLog: siteRun.log, exitCode: site.exitCode)
        let code = site.exitCode.map { "It exited with status \($0). " } ?? ""
        return code + (cause ?? "The last lines of the log are below.")
    }

    /// The end of the site's log while it runs, or after it stopped.
    @ViewBuilder
    func logsCard(_ site: Site) -> some View {
        if model.snapshot.isLive, site.state != .stopped || !siteRun.log.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionLabel(text: "Log")
                        Spacer()
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([siteRun.logFile(site.id)])
                        }
                        .font(.system(size: 11.5))
                    }
                    if siteRun.log.isEmpty {
                        Text("Nothing logged yet.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Text(siteRun.log.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(14)
                    }
                }
            }
            .task(id: site.id) {
                while !Task.isCancelled {
                    await siteRun.loadLog(site.id)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }
}
