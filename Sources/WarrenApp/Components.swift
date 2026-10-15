// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

struct StatusDot: View {
    let running: Bool

    var body: some View {
        Circle()
            .fill(Color.status(running: running))
            .frame(width: 8, height: 8)
    }
}

struct Chip: View {
    let text: String
    var tint: Color = .primary

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(tint == .primary ? Color.secondary : tint)
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct ServiceToggle: View {
    let isOn: Bool
    let change: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: change))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(.warrenAccent)
            .controlSize(.small)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.warrenCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.warrenHairline))
    }
}

struct AppMark: View {
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(LinearGradient(colors: [Color(red: 0.48, green: 0.94, blue: 0.72),
                                          Color(red: 0.18, green: 0.75, blue: 0.54)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay { ArchShape().stroke(Color(red: 0.02, green: 0.16, blue: 0.11),
                                          style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .padding(size * 0.24)
            }
    }
}

/// The burrow arch with its inner arch, drawn in a unit square.
struct ArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.45))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + h * 0.45), radius: w / 2,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + w * 0.3, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.3, y: rect.minY + h * 0.72))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + h * 0.72), radius: w * 0.2,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + w * 0.7, y: rect.maxY))
        return path
    }
}
