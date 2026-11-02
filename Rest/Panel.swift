import AppKit
import SwiftUI

/// Everything that drops out of the menu bar, as one sheet on one grid: the
/// time over a horizon, a table with its labels on the left edge and its values
/// on the right, and the two keys along the bottom.
struct Panel: View {
    @Bindable var rest: Rest

    var body: some View {
        VStack(spacing: 0) {
            HorizonScene(rest: rest)
            Hairline(color: Theme.muted)
            Table(rest: rest)
            Keys(rest: rest)
        }
        .frame(width: Theme.panelWidth)
        .background(Theme.paper)
        .onKeyPress(characters: ["q"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            NSApp.terminate(nil)
            return .handled
        }
        .contextMenu {
            Button("Quit Rest") { NSApp.terminate(nil) }
        }
    }
}

/// A half point rule across the sheet.
struct Hairline: View {
    var color = Theme.line

    var body: some View {
        Rectangle().fill(color).frame(height: 0.5)
    }
}

// MARK: Table

private struct Table: View {
    @Bindable var rest: Rest
    @State private var atLogin = false

    var body: some View {
        VStack(spacing: 0) {
            NextBreakRow(rest: rest)
            Hairline()
            AfterThatRow(rest: rest)
            Hairline()
            CallRow(rest: rest)
            Hairline()
            ToggleRow(title: "Posture reminders", on: rest.postureReminders) {
                rest.postureReminders.toggle()
            }
            .help("A reminder to sit up straight every \(Int(rest.settings.posture / 60)) minutes of work")
            Hairline()
            ToggleRow(title: "Open at login", on: atLogin) {
                rest.opensAtLogin = !atLogin
                atLogin = rest.opensAtLogin
            }
            Hairline()
        }
        .onAppear { atLogin = rest.opensAtLogin }
    }
}

/// A line of the table: a grey label on the left edge and its value on the
/// right. With an action, the whole line is the key.
private struct Row<Value: View>: View {
    let title: String
    var action: (() -> Void)?
    @ViewBuilder var value: (_ hovering: Bool) -> Value
    @State private var hovering = false

    var body: some View {
        let content = HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(Theme.muted)
                .fixedSize()
            value(hovering)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(hovering && action != nil ? Theme.hover : .clear)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(RowKey())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        } else {
            content
        }
    }
}

/// A row going down: it spans the sheet, so it darkens instead of shrinking.
private struct RowKey: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .overlay(Theme.ink.opacity(pressed ? 0.05 : 0))
            .animation(pressed ? Theme.keyDown : Theme.keyUp, value: pressed)
    }
}

/// The next break. Clicking pushes it back five minutes, which the line says
/// while the pointer's on it.
private struct NextBreakRow: View {
    let rest: Rest

    var body: some View {
        Row(title: "Next", action: { rest.postpone() }) { hovering in
            Text(hovering ? "5 more min" : value)
                .foregroundStyle(Theme.ink)
                .contentTransition(.opacity)
        }
        .help("Push the next break back five minutes")
    }

    private var value: String {
        let name = rest.nextIsLong ? "Long break" : "Short break"
        if case .call = rest.hold { return "\(name), after the call" }
        if case .video = rest.hold { return "\(name), after the video" }
        let length = rest.nextIsLong ? rest.settings.longBreak : rest.settings.shortBreak
        return "\(name), \(Self.describe(length))"
    }

    static func describe(_ seconds: TimeInterval) -> String {
        seconds >= 60 ? "\(Int(seconds / 60)) min" : "\(Int(seconds)) sec"
    }
}

private struct AfterThatRow: View {
    let rest: Rest

    var body: some View {
        Row(title: "After that") { _ in
            Text(value).foregroundStyle(Theme.ink)
        }
    }

    private var value: String {
        if rest.nextIsLong { return "Short" }
        let left = rest.settings.longEvery - rest.shortsSinceLong
        return "Long in \(left) \(left == 1 ? "break" : "breaks")"
    }
}

/// Who has the mic, if anyone, with the one colour while a call is on.
private struct CallRow: View {
    let rest: Rest
    private var meetings: MeetingDetector { rest.meetings }

    /// An app you told Rest to always ignore, holding the mic now. Clicking
    /// the row counts it as a call again.
    private var ignoredApp: MeetingDetector.App? {
        guard !meetings.inMeeting, meetings.microphones.contains(where: \.running) else { return nil }
        return meetings.micApps.first { rest.ignoredApps.contains($0.key) }
    }

    var body: some View {
        let live = meetings.inMeeting
        Row(title: title, action: ignoredApp.map { app in { rest.countAsCall(app) } }) { _ in
            HStack(spacing: 5) {
                if live {
                    Circle().fill(Theme.red).frame(width: 5, height: 5)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(value)
                    .foregroundStyle(Theme.ink)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
            }
            .animation(.easeOut(duration: 0.15), value: live)
        }
        .help(value)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard meetings.inMeeting else { return "Microphone" }
        if let app = meetings.meetingApp, MeetingDetector.listeners.contains(app.key) { return "Active" }
        return "On a call"
    }

    private var value: String {
        if meetings.inMeeting {
            if let app = meetings.meetingApp { return app.name }
            return meetings.cameraRunning ? "The camera" : "The mic"
        }
        if let ignoredApp { return "\(ignoredApp.name) is ignored. Click to count it" }
        if meetings.microphones.contains(where: \.running), let app = meetings.micApps.first(where: { meetings.ignoredUntilBreak.contains($0.key) }) {
            return "\(app.name) is ignored till the next break"
        }
        if meetings.microphones.contains(where: \.running), let other = meetings.micApps.first {
            return other.isSystem && other.name != "Siri" ? "The system is using the mic" : "\(other.name) is using the mic"
        }
        guard let mic = meetings.microphones.first(where: \.running) ?? meetings.microphones.first else { return "None found" }
        let others = meetings.microphones.count - 1
        return others > 0 ? "\(mic.name) and \(others) more" : mic.name
    }
}

/// A setting: its name, and a small dot on the right edge that fills from its
/// centre while it's on.
private struct ToggleRow: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Row(title: title, action: action) { _ in
            ZStack {
                Circle().strokeBorder(on ? Theme.ink : Theme.muted, lineWidth: 1)
                Circle()
                    .fill(Theme.ink)
                    .scaleEffect(on || reduceMotion ? 1 : 0.4)
                    .opacity(on ? 1 : 0)
                    .animation(Theme.keyUp, value: on)
            }
            .frame(width: 7, height: 7)
            .animation(.easeOut(duration: 0.12), value: on)
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: Keys

/// Pause on the left, and the one ink key: take a break.
private struct Keys: View {
    let rest: Rest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button(action: rest.togglePause) {
                HStack(spacing: 6) {
                    PauseGlyph(play: rest.isPaused ? 1 : 0)
                        .fill(Theme.ink)
                        .frame(width: 12, height: 12)
                        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24), value: rest.isPaused)
                    Text(rest.isPaused ? "Resume" : "Pause")
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(SheetKey())
            .frame(width: 112)
            .help(rest.isPaused ? "Start the clock again" : "Pause for an hour")
            .accessibilityLabel(rest.isPaused ? "Resume" : "Pause for an hour")

            Button(action: rest.breakNow) {
                Text("Take a break")
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SheetKey(primary: true))
            .disabled(rest.isOnBreak)
        }
        .font(.system(size: 13))
        .frame(height: 42)
    }
}

/// A key along the bottom of the sheet. It's built into the edge, so it
/// darkens when pressed instead of shrinking.
private struct SheetKey: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return Hovering { hovering in
            configuration.label
                .background {
                    if primary {
                        Theme.ink.overlay(Theme.paper.opacity(pressed ? 0.26 : hovering && isEnabled ? 0.14 : 0))
                    } else {
                        (pressed ? Theme.line : hovering ? Theme.hover : .clear)
                    }
                }
                .opacity(isEnabled ? 1 : 0.5)
                .animation(pressed ? Theme.keyDown : Theme.keyUp, value: pressed)
        }
    }
}

/// Pause's two bars fold into play's triangle: the bars' outer corners
/// close to a point, the same trick as Tuner's play and stop.
private struct PauseGlyph: Shape {
    /// 0 is pause, 1 is play.
    var play: Double

    var animatableData: Double {
        get { play }
        set { play = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * play }
        let cx = rect.midX, cy = rect.midY
        // Pause: two 3.2pt bars, 3pt apart. Play: one triangle, nudged right of centre.
        let left = [CGPoint(x: cx - 4.6, y: cy - 5), CGPoint(x: cx - 1.4, y: cy - 5), CGPoint(x: cx - 1.4, y: cy + 5), CGPoint(x: cx - 4.6, y: cy + 5)]
        let leftPlay = [CGPoint(x: cx - 3.2, y: cy - 5.5), CGPoint(x: cx + 1.1, y: cy - 3), CGPoint(x: cx + 1.1, y: cy + 3), CGPoint(x: cx - 3.2, y: cy + 5.5)]
        let right = [CGPoint(x: cx + 1.4, y: cy - 5), CGPoint(x: cx + 4.6, y: cy - 5), CGPoint(x: cx + 4.6, y: cy + 5), CGPoint(x: cx + 1.4, y: cy + 5)]
        let rightPlay = [CGPoint(x: cx + 1.1, y: cy - 3), CGPoint(x: cx + 5.4, y: cy), CGPoint(x: cx + 5.4, y: cy), CGPoint(x: cx + 1.1, y: cy + 3)]

        var path = Path()
        for (from, to) in [(left, leftPlay), (right, rightPlay)] {
            path.addLines(zip(from, to).map { CGPoint(x: mix($0.x, $1.x), y: mix($0.y, $1.y)) })
            path.closeSubpath()
        }
        return path
    }
}
