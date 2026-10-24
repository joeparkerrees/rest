import AppKit
import SwiftUI

/// Rest talks to you out of the notch, the way the Dynamic Island does on an
/// iPhone. In the last minute before a break the notch widens a little: the
/// mark on one side, the time until the break on the other. Five seconds out
/// it opens down into the warning, with a key to push the break back. When a
/// call starts it opens to say so, with a way out if it isn't a call. Macs
/// have no Dynamic Island of their own, so this is a black window drawn over
/// the notch to look part of it. Without a notch on the main display, the
/// warning is the white capsule under the menu bar instead, and calls show
/// only in the panel.
@MainActor
final class Island {
    static let flare: CGFloat = 6
    static let side: CGFloat = 44
    static let drawer: CGFloat = 54
    static let noticeDrawer: CGFloat = 96
    static let expandedWidth: CGFloat = 360
    static let noticeWidth: CGFloat = 420

    /// What the call notice says, and what its keys do.
    struct Call {
        /// "On a call in Arc", "Shazam is active", "Your camera is on".
        let title: String
        /// The app on the call; nil when it's only the camera.
        let name: String?
        let icon: NSImage?
        let ignore: () -> Void
        /// Always ignore the app; nil when there's no app to name.
        let always: (() -> Void)?
    }

    private let model = IslandModel()
    private var panel: IslandPanel?
    private let capsule = WarningWindow()
    /// Where the island is heading; `model` is what's drawn.
    private var mode: IslandModel.Mode = .hidden
    private var content: IslandModel.Content = .countdown
    private var generation = 0

    /// The main display, if it has a notch, and the notch's frame on it.
    private var notch: (screen: NSScreen, frame: NSRect)? {
        guard let screen = NSScreen.main, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let top = screen.safeAreaInsets.top
        return (screen, NSRect(x: left.maxX, y: screen.frame.maxY - top, width: right.minX - left.maxX, height: top))
    }

    static func icon(bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    // MARK: Countdown

    /// The last minute: the countdown beside the notch.
    func approach(remaining: TimeInterval) {
        guard let notch else { return }
        model.remaining = remaining
        guard mode != .compact || content != .countdown else { return }
        present(over: notch.frame)
        set(.compact, .countdown)
    }

    /// The warning, opened out of the notch.
    func warn(seconds: Int, long: Bool, length: TimeInterval, postpone: @escaping () -> Void) {
        guard let notch else {
            capsule.show(seconds: seconds, postpone: postpone)
            return
        }
        model.remaining = TimeInterval(seconds)
        model.long = long
        model.length = length
        model.postpone = postpone
        present(over: notch.frame)
        set(.expanded, .countdown)
        announce("\(long ? "Long" : "Short") break in \(seconds) seconds")
    }

    func update(seconds: Int) {
        model.remaining = TimeInterval(seconds)
        capsule.update(seconds: seconds)
    }

    func hideCountdown() {
        capsule.hide()
        if content == .countdown { collapse() }
    }

    // MARK: Calls

    /// A call has started. Closes by itself after a few seconds, unless the
    /// pointer is resting on it.
    func notice(_ call: Call) {
        guard let notch else { return }
        model.call = call
        present(over: notch.frame)
        set(.expanded, .call)
        dismiss(after: 8, generation: generation)
        announce("\(call.title). Your break will wait.")
    }

    func hideNotice() {
        if content == .call { collapse() }
    }

    private func dismiss(after seconds: TimeInterval, generation current: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, self.content == .call, self.mode == .expanded else { return }
                if self.model.hovering {
                    self.dismiss(after: 2, generation: current)
                } else {
                    self.collapse()
                }
            }
        }
    }

    // MARK: Window

    /// Shrinks back into the notch, then takes the window away.
    private func collapse() {
        guard mode != .hidden else { return }
        set(.hidden, content)
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, self.mode == .hidden else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func present(over notch: NSRect) {
        generation += 1
        model.notch = notch.size
        let size = model.windowSize
        let frame = NSRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height, width: size.width, height: size.height)
        let panel = self.panel ?? makePanel()
        panel.setFrame(frame, display: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func set(_ next: IslandModel.Mode, _ nextContent: IslandModel.Content) {
        guard next != mode || nextContent != content else { return }
        let growing = next.rank > mode.rank || (next == .expanded && nextContent != content)
        mode = next
        content = nextContent
        // Only the open island takes clicks; the slim countdown lets them
        // through to the menu bar under it.
        panel?.ignoresMouseEvents = next != .expanded
        let animation: Animation = if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            .easeOut(duration: 0.2)
        } else if growing {
            // A little overshoot as it opens, like the island; none as it closes.
            .spring(duration: 0.5, bounce: 0.22)
        } else {
            .spring(duration: 0.34, bounce: 0)
        }
        // Give a freshly shown window a frame at its old size before it morphs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [model] in
            MainActor.assumeIsolated {
                withAnimation(animation) {
                    model.mode = next
                    model.content = nextContent
                }
            }
        }
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    private func makePanel() -> IslandPanel {
        let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the menu bar, so it can sit over the notch.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: IslandView(model: model, close: { [weak self] in self?.hideNotice() }))
        self.panel = panel
        return panel
    }
}

/// Borderless windows are kept below the menu bar unless told otherwise.
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
@Observable
final class IslandModel {
    enum Mode {
        case hidden, compact, expanded
        var rank: Int { switch self { case .hidden: 0; case .compact: 1; case .expanded: 2 } }
    }

    enum Content { case countdown, call }

    var mode: Mode = .hidden
    var content: Content = .countdown
    var notch = CGSize(width: 185, height: 32)
    var hovering = false

    /// Seconds until the break starts.
    var remaining: TimeInterval = 0
    var long = false
    var length: TimeInterval = 30
    @ObservationIgnored var postpone: () -> Void = {}

    var call: Island.Call?

    /// The island's body, not counting the flares at its top corners.
    func size(for mode: Mode, _ content: Content) -> CGSize {
        switch mode {
        case .hidden:
            return notch
        case .compact:
            return CGSize(width: notch.width + 2 * Island.side, height: notch.height)
        case .expanded:
            // Odd or even like the notch, so it centres on whole points
            // instead of sitting half a point off.
            let width = max(notch.width + 2 * Island.side, content == .call ? Island.noticeWidth : Island.expandedWidth)
            let parity: CGFloat = (width - notch.width).truncatingRemainder(dividingBy: 2) == 0 ? 0 : 1
            return CGSize(width: width + parity, height: notch.height + (content == .call ? Island.noticeDrawer : Island.drawer))
        }
    }

    func radius(for mode: Mode) -> CGFloat {
        switch mode {
        case .hidden: 8
        case .compact: 11
        case .expanded: 22
        }
    }

    /// Big enough for the largest island, flares and all.
    var windowSize: CGSize {
        let warning = size(for: .expanded, .countdown)
        let notice = size(for: .expanded, .call)
        return CGSize(width: max(warning.width, notice.width) + 2 * Island.flare, height: max(warning.height, notice.height))
    }
}

struct IslandView: View {
    let model: IslandModel
    var close: () -> Void = {}

    var body: some View {
        let size = model.size(for: model.mode, model.content)
        let shape = IslandShape(flare: Island.flare, radius: model.radius(for: model.mode))
        shape
            .fill(.black)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    band
                    if model.mode == .expanded {
                        Group {
                            switch model.content {
                            case .countdown: warning
                            case .call: notice
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -6)).animation(.easeOut(duration: 0.22).delay(0.1)),
                            removal: .opacity.animation(.easeOut(duration: 0.08))
                        ))
                    }
                }
                .padding(.horizontal, Island.flare)
                .opacity(model.mode == .hidden ? 0 : 1)
            }
            .clipShape(shape)
            .onHover { model.hovering = $0 }
            .frame(width: size.width + 2 * Island.flare, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
    }

    /// Beside the notch. Centred in the slim island; out to the drawer's
    /// edges once it opens.
    private var band: some View {
        let open = model.mode == .expanded
        return HStack(spacing: 0) {
            leading
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: open ? .leading : .center)
            Color.clear.frame(width: model.notch.width)
            trailing
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: open ? .trailing : .center)
        }
        .padding(.horizontal, open ? 18 : 0)
        .frame(height: model.notch.height)
    }

    /// The mark, or the app on the call.
    @ViewBuilder
    private var leading: some View {
        if model.content == .call, let icon = model.call?.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
        } else {
            Image(nsImage: MenuBarIcon.markImage(size: 14))
                .renderingMode(.template)
                .foregroundStyle(.white)
        }
    }

    /// The time until the break, or the on-air light during a call.
    @ViewBuilder
    private var trailing: some View {
        if model.content == .call {
            Circle().fill(Theme.red).frame(width: 6, height: 6)
                .accessibilityHidden(true)
        } else {
            Text(Clock.format(model.remaining))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeOut(duration: 0.2), value: Int(model.remaining.rounded(.up)))
        }
    }

    private var warning: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.long ? "Long break" : "Short break")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text("Look away for \(Self.describe(model.length))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            IslandButton(title: "5 more min") { model.postpone() }
        }
        .padding(.horizontal, 18)
        .frame(height: Island.drawer)
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.call?.title ?? "")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Your break will wait until you’re done")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                CloseKey(action: close)
            }
            HStack(spacing: 8) {
                if let call = model.call {
                    IslandButton(title: "Ignore till next break", action: call.ignore)
                    if let always = call.always, let name = call.name {
                        IslandButton(title: "Always ignore \(name)", action: always)
                    }
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .frame(height: Island.noticeDrawer, alignment: .top)
    }

    static func describe(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) seconds" }
        let minutes = total / 60
        return minutes == 1 ? "a minute" : "\(minutes) minutes"
    }
}

/// The quiet key, turned out for the black island.
private struct IslandButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(title, action: action)
            .buttonStyle(IslandKey(hovering: hovering))
            .onHover { hovering = $0 }
    }
}

private struct IslandKey: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.white.opacity(pressed ? 0.26 : hovering ? 0.2 : 0.14), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(pressed ? Theme.keyDown : Theme.keyUp, value: pressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A small round close key; its hit area is larger than it looks.
private struct CloseKey: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.6))
                .frame(width: 22, height: 22)
                .background(.white.opacity(hovering ? 0.18 : 0.1), in: Circle())
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-4)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel("Close")
    }
}

/// The island's outline: flat along the top of the screen, flaring out at the
/// top corners into the bezel like the notch does, rounded at the bottom.
struct IslandShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let left = rect.minX + flare
        let right = rect.maxX - flare
        let r = max(0, min(radius, (right - left) / 2, rect.height - flare))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: left, y: rect.minY), tangent2End: CGPoint(x: left, y: rect.minY + flare), radius: flare)
        path.addArc(tangent1End: CGPoint(x: left, y: rect.maxY), tangent2End: CGPoint(x: left + r, y: rect.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: right, y: rect.maxY), tangent2End: CGPoint(x: right, y: rect.maxY - r), radius: r)
        path.addArc(tangent1End: CGPoint(x: right, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: flare)
        path.closeSubpath()
        return path
    }
}
