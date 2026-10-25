import AppKit
import SwiftUI

/// Everything that drops out of the menu bar: the picture, a row of keys,
/// a white card of rows, and a footer, on the grey ground.
struct Panel: View {
    @Bindable var rest: Rest

    var body: some View {
        VStack(spacing: Theme.gutter) {
            HorizonScene(rest: rest)
            Keys(rest: rest)
            Rows(rest: rest)
            Footer(rest: rest)
        }
        .padding(Theme.gutter)
        .frame(width: Theme.panelWidth)
        .background(Theme.ground)
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

// MARK: Keys

private struct Keys: View {
    let rest: Rest

    var body: some View {
        HStack(spacing: 10) {
            PauseKey(rest: rest)
            Button(action: rest.breakNow) {
                Text("Take a break now")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Capsule())
            }
            .buttonStyle(QuietKey())
            .disabled(rest.isOnBreak)
        }
    }
}

/// The round ink key: pause the clock for an hour, or start it again.
private struct PauseKey: View {
    let rest: Rest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: rest.togglePause) {
            ZStack {
                Circle().fill(Theme.ink)
                PauseGlyph(play: rest.isPaused ? 1 : 0)
                    .fill(Theme.paper)
                    .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24), value: rest.isPaused)
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(InkKey(reduceMotion: reduceMotion))
        .help(rest.isPaused ? "Start the clock again" : "Pause for an hour")
        .accessibilityLabel(rest.isPaused ? "Resume" : "Pause for an hour")
    }
}

/// A Braun key: goes down quickly and comes straight back up, no wobble.
private struct InkKey: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(pressed ? Theme.keyDown : Theme.keyUp, value: pressed)
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

// MARK: Rows

private struct Rows: View {
    let rest: Rest

    var body: some View {
        VStack(spacing: 0) {
            CallRow(rest: rest)
            divider
            NextBreakRow(rest: rest)
        }
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var divider: some View {
        Rectangle().fill(Theme.ground).frame(height: 1).padding(.leading, 48)
    }
}

/// A row: a 26pt badge, a title and a grey line under it.
private struct Row<Badge: View>: View {
    let title: String
    let detail: String
    var live = false
    var action: (() -> Void)?
    @ViewBuilder var badge: () -> Badge
    @State private var hovering = false

    private static var capTop: CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        return font.ascender - font.capHeight
    }

    var body: some View {
        let content = HStack(alignment: .top, spacing: 10) {
            badge()
                .frame(width: 26, height: 26)
                .padding(.top, Self.capTop)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: title)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .padding(.trailing, 24)
        .padding(.vertical, 10)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Theme.red)
                .frame(width: 5, height: 5)
                .opacity(live ? 1 : 0)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .animation(.easeOut(duration: 0.15), value: live)
        }
        .background(hovering && action != nil ? Theme.hover : .clear)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        } else {
            content
        }
    }
}

/// A round badge with a symbol, white, or red while it's live.
private struct Badge: View {
    let symbol: String
    var red = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(red ? Color.white : Theme.ink)
            .frame(width: 26, height: 26)
            .background {
                Circle().fill(red ? Theme.red : Theme.paper)
                if !red { Circle().strokeBorder(Theme.line, lineWidth: 1) }
            }
            .animation(.easeOut(duration: 0.15), value: red)
    }
}

/// Who has the mic, if anyone. Red, like NTS 1's key, while a call is on.
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
        let mic = meetings.microphones.first(where: \.running) ?? meetings.microphones.first
        Row(title: title, detail: detail(mic: mic), live: live, action: ignoredApp.map { app in { rest.countAsCall(app) } }) {
            Badge(symbol: meetings.cameraRunning && meetings.watchesCamera ? "video.fill" : "mic.fill", red: live)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard meetings.inMeeting else { return "No call" }
        if let app = meetings.meetingApp { return MeetingDetector.listeners.contains(app.key) ? "\(app.name) is active" : "\(app.name) is on a call" }
        return meetings.cameraRunning ? "The camera is on" : "The mic is on"
    }

    private func detail(mic: MeetingDetector.Microphone?) -> String {
        if meetings.inMeeting { return "Breaks start after the call" }
        if let ignoredApp { return "\(ignoredApp.name) is ignored. Click to count it" }
        if meetings.microphones.contains(where: \.running), let app = meetings.micApps.first(where: { meetings.ignoredUntilBreak.contains($0.key) }) {
            return "\(app.name) is ignored till the next break"
        }
        if meetings.microphones.contains(where: \.running), let other = meetings.micApps.first {
            return other.isSystem && other.name != "Siri" ? "The system is using the mic" : "\(other.name) is using the mic"
        }
        guard let mic else { return "No microphone found" }
        let others = meetings.microphones.count - 1
        return others > 0 ? "\(mic.name) and \(others) more" : mic.name
    }
}

private struct NextBreakRow: View {
    let rest: Rest

    var body: some View {
        let long = rest.nextIsLong
        let length = long ? rest.settings.longBreak : rest.settings.shortBreak
        let left = rest.settings.longEvery - rest.shortsSinceLong
        Row(title: "\(long ? "Long" : "Short") break, \(Self.describe(length))", detail: long ? "Then short breaks again" : "A long break after \(left) more", action: { rest.postpone() }) {
            Text(long ? "L" : "S")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background {
                    Circle().fill(Theme.paper)
                    Circle().strokeBorder(Theme.line, lineWidth: 1)
                }
        }
        .help("Push the next break back five minutes")
    }

    static func describe(_ seconds: TimeInterval) -> String {
        seconds >= 60 ? "\(Int(seconds / 60)) min" : "\(Int(seconds)) sec"
    }
}

// MARK: Footer

private struct Footer: View {
    let rest: Rest
    @State private var atLogin = false
    @State private var hovering = false

    var body: some View {
        HStack {
            Spacer()
            Button {
                rest.opensAtLogin = !atLogin
                atLogin = rest.opensAtLogin
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(atLogin ? Theme.ink : .clear)
                        .overlay(Circle().strokeBorder(atLogin ? Theme.ink : Theme.muted, lineWidth: 1))
                        .frame(width: 7, height: 7)
                    Text("Open at login")
                }
                .foregroundStyle(hovering || atLogin ? Theme.ink : Theme.muted)
                .contentShape(Rectangle())
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: atLogin)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 4)
        .onAppear { atLogin = rest.opensAtLogin }
    }
}
