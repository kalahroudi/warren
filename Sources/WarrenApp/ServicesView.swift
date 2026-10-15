// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

struct ServicesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Services",
                       subtitle: "One-click databases and the usual suspects. Data lives in ~/Warren/data.",
                       preview: model.snapshot.previewSections.contains("Services"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(model.snapshot.services) { service in
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.name).font(.system(size: 14.5, weight: .semibold))
                                    Text(service.kind).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                ServiceToggle(isOn: service.running) { model.setService(service.id, running: $0) }
                            }
                            HStack {
                                Text(verbatim: "localhost:" + String(service.port))
                                Spacer()
                                Text(service.running ? "\(service.memoryMB) MB" : "stopped")
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(24)
    }
}
