// SPDX-License-Identifier: Apache-2.0

import AppKit

/// Monochrome template glyph: macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3, y: 2))
            path.line(to: NSPoint(x: 3, y: 9))
            path.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6, startAngle: 180, endAngle: 0, clockwise: true)
            path.line(to: NSPoint(x: 15, y: 2))
            path.move(to: NSPoint(x: 6.5, y: 2))
            path.line(to: NSPoint(x: 6.5, y: 6))
            path.appendArc(withCenter: NSPoint(x: 9, y: 6), radius: 2.5, startAngle: 180, endAngle: 0, clockwise: true)
            path.line(to: NSPoint(x: 11.5, y: 2))
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
