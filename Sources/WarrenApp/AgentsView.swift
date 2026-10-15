// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

struct AgentsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let agents = model.snapshot.agents
        return VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Agents",
                       subtitle: "Warren speaks MCP, so Claude Code, Cursor and friends can run your local stack.",
                       preview: model.snapshot.previewSections.contains("Agents"))
            HStack(alignment: .top, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { StatusDot(running: true); Text("MCP server").font(.system(
                            size: 14.5,
                            weight: .semibold
                        )) }
                        Text(agents.endpoint).font(.system(size: 12.5, design: .monospaced))
                        SectionLabel(text: "Connected clients")
                        ForEach(agents.clients) { client in
                            HStack {
                                StatusDot(running: client.connected)
                                Text(client.name)
                                Spacer()
                                Text(client.connected ? "connected" : "not set up").foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What agents may do").font(.system(size: 14.5, weight: .semibold))
                        Text("Reads are always on. Risky actions ask you first.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        ForEach(agents.permissions) { permission in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(permission.tool).font(.system(size: 12.5, design: .monospaced))
                                    Text(permission.summary).font(.system(size: 11.5)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Chip(text: permission.asksFirst ? "Ask first" : "Auto",
                                     tint: permission.asksFirst ? .orange : .warrenAccent)
                            }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity").font(.system(size: 14.5, weight: .semibold))
                    ForEach(agents.activity) { item in
                        HStack(spacing: 12) {
                            Text(item.time).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                            Text(item.client).frame(width: 100, alignment: .leading)
                            Text(item.call).font(.system(size: 12.5, design: .monospaced))
                            Spacer()
                            Text(item.result).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12.5))
                    }
                }
            }
            Spacer()
        }
        .padding(24)
    }
}
