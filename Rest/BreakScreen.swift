import AppKit
import SwiftUI

/// The break covers every display with the landscape: sky over land. The
/// main display has the time left in the sky and the sight to look for on
/// the horizon. Esc twice, or
/// Skip, ends it once the first few seconds are up.
struct BreakScreen: View {
    let rest: Rest
    let sight: Sight
    /// Only the main display carries the time, the sight and the controls.
    var isMain = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    /// The land's share of the screen's height.
    static let land: CGFloat = 0.32

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let horizon = size.height * (1 - Self.land)
            ZStack(alignment: .topLeading) {
                Theme.sky
                Theme.land
                    .frame(height: size.height - horizon)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                if isMain {
                    foreground(size: size, horizon: horizon)
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown || reduceMotion ? 0 : 6)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // The window fades in first; the sight and the time settle in
            // just behind it.
            withAnimation(Theme.settle.delay(0.12)) { shown = true }
        }
        .accessibilityElement(children: .contain)
    }

    private func foreground(size: CGSize, horizon: CGFloat) -> some View {
        let figure = (size.height * 0.16).rounded()
        return ZStack(alignment: .topLeading) {
            SightFigure(sight: sight, size: figure)
                .position(x: size.width / 2, y: horizon - figure / 2)
            clock
                .position(x: size.width / 2, y: horizon * 0.36)
            VStack(spacing: 0) {
                Text("Try and look at \(sight.thing)")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.onLand)
                    .multilineTextAlignment(.center)
                    .padding(.top, (size.height - horizon) * 0.24)
                Spacer(minLength: 24)
                SkipKey(rest: rest)
                    .padding(.bottom, 32)
            }
            .frame(width: size.width, height: size.height - horizon)
            .offset(y: horizon)
        }
        .frame(width: size.width, height: size.height)
    }

    private var clock: some View {
        let isLong = if case let .onBreak(long, _, _) = rest.phase { long } else { false }
        return VStack(spacing: 4) {
            Text(Clock.format(rest.breakRemaining))
                .font(.system(size: 72, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeOut(duration: 0.2), value: Int(rest.breakRemaining.rounded(.up)))
            Text(isLong ? "Long break" : "Short break")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLong ? "Long break" : "Short break")
        .accessibilityValue("\(Int(rest.breakRemaining.rounded())) seconds left")
    }
}

/// Skip is locked for the first few seconds of the break. The lock is a fill
/// that drains out of the key from right to left, and the key works as soon
/// as it's gone.
private struct SkipKey: View {
    let rest: Rest
    @State private var fill: CGFloat = 1
    @State private var unlocked = false

    var body: some View {
        Button(action: rest.skip) {
            Text("Skip")
                .frame(minWidth: 88, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(LandKey(fill: fill))
        .disabled(!unlocked)
        .font(.system(size: 12))
        .foregroundStyle(Theme.onLand.opacity(unlocked ? 1 : 0.55))
        .animation(.easeOut(duration: 0.15), value: unlocked)
        .help("Or press Esc twice")
        .accessibilityHint(unlocked ? "" : "Available after the first few seconds")
        .task {
            let left = rest.skipLockLeft
            guard left > 0 else {
                fill = 0
                unlocked = true
                return
            }
            withAnimation(.linear(duration: left)) { fill = 0 }
            try? await Task.sleep(for: .seconds(left))
            unlocked = true
        }
    }
}

/// A key standing on the land: a hairline capsule in the sky's colour, with
/// the lock's fill drawn in it from the left edge.
struct LandKey: ButtonStyle {
    /// How much of the key is filled, from the left edge.
    var fill: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .padding(.horizontal, 12)
            .background {
                Capsule()
                    .fill(Theme.onLand.opacity(pressed ? 0.16 : 0.06))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.onLand.opacity(0.2))
                            .scaleEffect(x: fill, anchor: .leading)
                    }
                    .clipShape(Capsule())
            }
            .overlay(Capsule().strokeBorder(Theme.onLand.opacity(0.35), lineWidth: 1))
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .animation(pressed ? Theme.keyDown : Theme.keyUp, value: pressed)
    }
}

/// A quiet text key: paper with a hairline, dips when pressed.
struct QuietKey: ButtonStyle {
    /// How much of the key is filled, from the left edge.
    var fill: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .padding(.horizontal, 12)
            .background {
                Capsule()
                    .fill(Theme.paper)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.line)
                            .scaleEffect(x: fill, anchor: .leading)
                    }
                    .clipShape(Capsule())
            }
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(pressed ? Theme.keyDown : Theme.keyUp, value: pressed)
    }
}

// MARK: Windows

/// One borderless window per display, above everything, on every Space.
@MainActor
final class BreakWindows {
    private var windows: [NSWindow] = []
    private var escMonitor: Any?
    private var lastEsc: Date?

    func show(rest: Rest, sight: Sight) {
        hideNow()
        let main = NSScreen.main ?? NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = CoverWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.contentView = NSHostingView(rootView: BreakScreen(rest: rest, sight: sight, isMain: screen == main))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first { $0.screen == main }?.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0, 0.5, 0.2, 1)
            for window in windows { window.animator().alphaValue = 1 }
        }

        // Esc twice within a second skips, once skipping is allowed.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated {
                let now = Date()
                if let last = self?.lastEsc, now.timeIntervalSince(last) < 1 {
                    rest.skip()
                    self?.lastEsc = nil
                } else {
                    self?.lastEsc = now
                }
            }
            return nil
        }
    }

    /// Leaves quicker and quieter than it arrived.
    func hide() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
        let leaving = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for window in leaving { window.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated {
                for window in leaving { window.orderOut(nil) }
            }
        })
    }

    private func hideNow() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }
}

/// Borderless windows can't take key focus by default, and the break needs
/// it for Esc.
private final class CoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The 5-second warning on a Mac without a notch: a small white capsule under
/// the menu bar with the seconds counting down. Clicking it pushes the break
/// back five minutes.
@MainActor
final class WarningWindow {
    private var panel: NSPanel?
    private let model = WarningModel()

    func show(seconds: Int, postpone: @escaping () -> Void) {
        model.seconds = seconds
        if panel == nil {
            let size = NSSize(width: 236, height: 40)
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: WarningPill(model: model, postpone: postpone))
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 10))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = 1
        }
    }

    func update(seconds: Int) {
        model.seconds = seconds
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

@MainActor
@Observable
final class WarningModel {
    var seconds = 5
}

private struct WarningPill: View {
    let model: WarningModel
    let postpone: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: postpone) {
            HStack(spacing: 8) {
                Text("Break in \(model.seconds)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.15), value: model.seconds)
                Spacer(minLength: 4)
                Text(hovering ? "Not now, 5 min" : "Click for 5 min")
                    .foregroundStyle(Theme.muted)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(hovering ? Theme.hover : Theme.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
