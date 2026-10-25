import AppKit
import SwiftUI

/// The last few seconds before a break, beside the pointer: a small ink
/// disc with the seconds counting down in it. It's there so a break doesn't
/// start without warning while you're looking nowhere near the notch. It
/// follows the pointer from screen to screen, never takes clicks, and moves
/// to the other side of the pointer near a screen's edge.
@MainActor
final class CursorCountdown: NSObject {
    static let size: CGFloat = 30
    /// From the pointer's hotspot to the dial's centre, clear of the arrow.
    static let offset: CGFloat = 30
    /// Room round the dial for its shadow.
    static let margin: CGFloat = 10

    private let model = CursorModel()
    private var panel: NSPanel?
    private var link: CADisplayLink?
    private var pointer: NSPoint?
    private var generation = 0

    /// Counts down to `until`.
    func show(until: Date) {
        // The clock ticks once a second, a fraction early or late; only a
        // real change moves the bead.
        if model.shown, abs(until.timeIntervalSince(model.until)) < 1 { return }
        generation += 1
        model.until = until
        let panel = self.panel ?? makePanel()
        pointer = nil
        follow()
        if !panel.isVisible { panel.orderFrontRegardless() }
        if link == nil, let view = panel.contentView {
            let link = view.displayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        guard !model.shown else { return }
        withAnimation(Theme.arrive) { model.shown = true }
    }

    /// Fades out quicker than it arrived, then takes the window away.
    func hide() {
        guard model.shown else { return }
        withAnimation(Theme.leave) { model.shown = false }
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, !self.model.shown else { return }
                self.link?.invalidate()
                self.link = nil
                self.panel?.orderOut(nil)
            }
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        follow()
    }

    /// Moves the window with the pointer, on every frame the pointer moved.
    private func follow() {
        let mouse = NSEvent.mouseLocation
        guard mouse != pointer, let panel else { return }
        pointer = mouse
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let centre = Self.centre(for: mouse, in: screen?.frame ?? .infinite)
        let side = Self.size + 2 * Self.margin
        panel.setFrameOrigin(NSPoint(x: (centre.x - side / 2).rounded(), y: (centre.y - side / 2).rounded()))
    }

    /// Below and to the right of the pointer, clear of the arrow, and on the
    /// other side of it wherever that would run off the screen. In screen
    /// points, which count up from the bottom.
    static func centre(for pointer: NSPoint, in bounds: NSRect) -> NSPoint {
        let reach = offset + size / 2
        let x = pointer.x + reach > bounds.maxX ? pointer.x - offset : pointer.x + offset
        let y = pointer.y - reach < bounds.minY ? pointer.y + offset : pointer.y - offset
        return NSPoint(x: x, y: y)
    }

    private func makePanel() -> NSPanel {
        let side = Self.size + 2 * Self.margin
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Over full screen apps and the menu bar, under the break itself.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: CursorCountdownView(model: model))
        self.panel = panel
        return panel
    }
}

@MainActor
@Observable
final class CursorModel {
    var shown = false
    /// When the break starts.
    var until = Date()
}

private struct CursorCountdownView: View {
    let model: CursorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !model.shown)) { context in
            let left = max(0, model.until.timeIntervalSince(context.date))
            CursorDial(seconds: Int(left.rounded(.up)))
        }
        .opacity(model.shown ? 1 : 0)
        .scaleEffect(model.shown || reduceMotion ? 1 : 0.9)
        .frame(width: CursorCountdown.size + 2 * CursorCountdown.margin, height: CursorCountdown.size + 2 * CursorCountdown.margin)
        .accessibilityHidden(true)
    }
}

/// A 30 point ink disc with the seconds in it, like the pause key, and a
/// shadow so it stands out over whatever's under the pointer.
struct CursorDial: View {
    let seconds: Int
    var size: CGFloat = CursorCountdown.size

    var body: some View {
        Text("\(seconds)")
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.paper)
            .contentTransition(.numericText(countsDown: true))
            .animation(.easeOut(duration: 0.2), value: seconds)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.ink).shadow(color: .black.opacity(0.18), radius: 4, y: 1.5))
    }
}
