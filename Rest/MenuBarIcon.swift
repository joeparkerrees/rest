import AppKit

/// Rest's mark with what's happening beside it:
/// the minutes until the next break, "On a call" while a call holds the
/// break back, and the time left during a break. Dimmed while the clock is
/// stopped for any other reason.
enum MenuBarIcon {
    enum Mark: CaseIterable {
        /// The panel's picture in small: a rounded frame with the land
        /// filled along the bottom and the sun in the sky.
        case picture
        /// A ring with its lower half filled: an eyelid closing, or the sun going down.
        case lid
        /// A solid disc with a slot knocked out: a closed eye.
        case slot
        /// A solid disc with the dial's bead knocked out at twelve.
        case bead
    }

    static let mark: Mark = .picture

    static func image(text: String, dimmed: Bool, mark: Mark = mark) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 0)
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular),
            .foregroundColor: NSColor.black,
        ])
        let textSize = label.size()
        let markSize: CGFloat = 14
        let gap: CGFloat = 5
        let width = markSize + gap + ceil(textSize.width) + 1
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { rect in
            // Template images keep their alpha, so dimming greys in either menu bar.
            if dimmed { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
            NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            draw(mark, in: CGRect(x: 0, y: (rect.height - markSize) / 2, width: markSize, height: markSize))
            NSGraphicsContext.current?.cgContext.endTransparencyLayer()
            label.draw(at: CGPoint(x: markSize + gap, y: rect.midY - textSize.height / 2 + 0.5))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The mark alone, for drawing in white inside the island.
    static func markImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(mark, in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ mark: Mark, in box: CGRect) {
        NSColor.black.set()
        let disc = box.insetBy(dx: 0.5, dy: 0.5)
        switch mark {
        case .picture:
            // The stroke's outer edge sits half a point in, like the other marks.
            let frame = box.insetBy(dx: 1.15, dy: 1.15)
            let outline = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.3
            outline.stroke()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3).addClip()
            NSBezierPath(rect: CGRect(x: box.minX, y: box.minY, width: box.width, height: 5.5)).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSBezierPath(ovalIn: CGRect(x: box.minX + 7.6, y: box.minY + 7.4, width: 3.2, height: 3.2)).fill()
        case .lid:
            let outline = NSBezierPath(ovalIn: disc.insetBy(dx: 0.6, dy: 0.6))
            outline.lineWidth = 1.2
            outline.stroke()
            // The lower half, filled: clip the disc to below the middle.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: CGRect(x: disc.minX, y: disc.minY, width: disc.width, height: disc.height / 2)).addClip()
            NSBezierPath(ovalIn: disc).fill()
            NSGraphicsContext.restoreGraphicsState()
        case .slot:
            NSBezierPath(ovalIn: disc).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let slot = CGRect(x: disc.midX - 3.4, y: disc.midY - 1.6, width: 6.8, height: 1.8)
            NSBezierPath(roundedRect: slot, xRadius: 0.9, yRadius: 0.9).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        case .bead:
            NSBezierPath(ovalIn: disc).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let bead = CGRect(x: disc.midX - 1.9, y: disc.maxY - 3.2 - 3.8, width: 3.8, height: 3.8)
            NSBezierPath(ovalIn: bead).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }
    }
}
