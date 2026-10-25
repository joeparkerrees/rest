import AppKit
import SwiftUI

/// Flat, Braun-leaning palette: white objects on a pale grey ground,
/// near-black ink, greys for everything secondary and a single Braun red.
/// In dark mode the objects are charcoal on a darker ground with pale ink,
/// so they still sit a step above it, and the red stays the same. The
/// landscape is drawn in the same greys, with the sights in ink.
enum Theme {
    static let ink = Color(light: 0x1D1D1D, dark: 0xECECEC)
    static let paper = Color(light: 0xFFFFFF, dark: 0x2A2A2A)
    static let ground = Color(light: 0xEEEEEE, dark: 0x1A1A1A)
    static let line = Color(light: 0xDDDDDD, dark: 0x3A3A3A)
    static let faint = Color(light: 0xC8C8C8, dark: 0x4C4C4C)
    static let muted = Color(light: 0xA1A1A1, dark: 0x8E8E8E)
    static let hover = Color(light: 0xF6F6F6, dark: 0x323232)
    /// The land along the bottom of the panel's picture and the break screen.
    static let land = faint
    /// The one colour, sampled from a button on Dieter Rams's T 1000: the
    /// on-air dots while a call has the mic.
    static let red = Color(hex: 0xE0330C)

    static let panelWidth: CGFloat = 280
    static let gutter: CGFloat = 12
    static let cardRadius: CGFloat = 12

    /// Settle: items land fast and ease the last few pixels.
    static let settle = Animation.timingCurve(0, 0.5, 0.2, 1, duration: 0.35)
    /// Detent-to-detent travel for the tuning bead, when you drag or click.
    static let detent = Animation.snappy(duration: 0.26, extraBounce: 0)
    /// Things arriving under the pointer: ease-out-quint, no overshoot.
    static let arrive = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    /// Things leaving: quicker and quieter than they arrived.
    static let leave = Animation.easeOut(duration: 0.12)
    /// A key going down, and coming back up without a wobble.
    static let keyDown = Animation.easeOut(duration: 0.08)
    static let keyUp = Animation.spring(duration: 0.2, bounce: 0)
    /// The one-time sweep round the dial: eases in, travels, eases to a stop.
    static let sweep = Animation.timingCurve(0.77, 0, 0.18, 1, duration: 1.2)
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// Follows the system appearance, or whatever the view's colour scheme is set to.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
