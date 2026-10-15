// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension Color {
    /// Mint accent, darkened in light appearance so text and fills keep their contrast.
    static let warrenAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.37, green: 0.90, blue: 0.66, alpha: 1)
            : NSColor(srgbRed: 0.04, green: 0.50, blue: 0.33, alpha: 1)
    })

    static let warrenCard = Color.primary.opacity(0.05)
    static let warrenHairline = Color.primary.opacity(0.08)

    static func status(running: Bool) -> Color {
        running ? .warrenAccent : Color.secondary.opacity(0.6)
    }
}
