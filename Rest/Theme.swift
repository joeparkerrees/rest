import AppKit
import SwiftUI

/// A landscape: a pale sky over dark green land, with a red sun. The panel
/// sits on a paler haze so the sky reads as a picture, and its cards are
/// white. In dark mode it's the same scene at night, and the sun stays red.
enum Theme {
    static let haze = Color(light: 0xEDF2F4, dark: 0x0F161C)
    static let sky = Color(light: 0xDCE8EE, dark: 0x34495A)
    static let land = Color(light: 0x1F3A2E, dark: 0x0A130F)
    /// The round pause key: the land in daylight, a lighter green at night
    /// so it still shows on the dark haze.
    static let key = Color(light: 0x1F3A2E, dark: 0x2F4A3D)
    /// Text and keys standing on the land.
    static let onLand = Color(light: 0xDCE8EE, dark: 0xC5D3CC)
    static let ink = Color(light: 0x1F3A2E, dark: 0xE3EBE7)
    static let paper = Color(light: 0xFFFFFF, dark: 0x1F2B35)
    static let line = Color(light: 0xD3DEE3, dark: 0x2E3C47)
    static let faint = Color(light: 0xB4C6CE, dark: 0x41525D)
    static let muted = Color(light: 0x566C67, dark: 0xA3B3B0)
    static let hover = Color(light: 0xF3F7F9, dark: 0x273540)
    /// The sun, and the on-air dots while a call has the mic.
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
