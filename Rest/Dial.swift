import SwiftUI

/// Tuner's dial as a clock: a white disc with a dot for each minute of work,
/// like the index on a Braun clock, and the black bead riding round as the
/// minutes pass. The bead goes hollow while the clock is stopped: paused,
/// away, or holding a break for a call. The middle says what's happening and
/// how long is left.
struct ClockDial: View {
    let rest: Rest
    var size: CGFloat = Theme.panelWidth - Theme.gutter * 2

    private var radius: CGFloat { size / 2 }
    private var ringRadius: CGFloat { radius - 17.5 }
    private var minutes: Int { max(1, Int((rest.settings.work / 60).rounded())) }

    /// The clock isn't moving: paused, away, or a break waiting on a call.
    private var stopped: Bool {
        rest.isPaused || rest.away || rest.hold != nil
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.paper)
            DotRing(count: minutes, lit: rest.isOnBreak ? 0 : Int(rest.progress * Double(minutes)), inset: 17.5)
            Bead(hollow: stopped)
                .offset(y: -ringRadius)
                .rotationEffect(.degrees(rest.progress * 360))
                // One second of travel per tick reads as a steady hand; a
                // reset to twelve should jump, not sweep backwards.
                .animation(rest.progress > 0.002 ? .linear(duration: 1) : nil, value: rest.progress)
                .animation(.easeOut(duration: 0.2), value: stopped)
            Readout(rest: rest)
                .frame(width: (ringRadius - 26) * 2 - 12)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

/// The dots that make the circle. Minutes already worked turn from the faint
/// grey to the muted one, so the dial fills in like a clock face being read.
struct DotRing: View {
    let count: Int
    let lit: Int
    var inset: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            let ring = radius - inset
            ForEach(0..<count, id: \.self) { index in
                let angle = Double(index) / Double(count) * 2 * .pi
                Circle()
                    .fill(index < lit ? Theme.muted : Theme.faint)
                    .frame(width: 3, height: 3)
                    .position(x: radius + ring * sin(angle), y: radius - ring * cos(angle))
                    .animation(.easeOut(duration: 0.15), value: lit)
            }
        }
    }
}

/// The bead from Tuner: solid while the clock runs, a ring while it's stopped.
struct Bead: View {
    let hollow: Bool

    var body: some View {
        ZStack {
            Circle().fill(Theme.ink).opacity(hollow ? 0 : 1)
            Circle()
                .fill(Theme.paper)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
                .opacity(hollow ? 1 : 0)
        }
        .frame(width: 7, height: 7)
    }
}

/// The middle of the dial.
private struct Readout: View {
    let rest: Rest

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                // Tuner's playing dot as an on-air light: red only while a call has the mic.
                if rest.meetings.inMeeting {
                    Circle().fill(Theme.red).frame(width: 5, height: 5)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(status)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .animation(Theme.settle, value: status)

            Text(Clock.format(rest.isOnBreak ? rest.breakRemaining : rest.remaining))
                .font(.system(size: 34, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeOut(duration: 0.2), value: Int(rest.remaining))

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
        .multilineTextAlignment(.center)
    }

    private var status: String {
        if rest.isOnBreak { return "On a break" }
        if rest.isPaused { return "Paused" }
        if case .call = rest.hold { return MeetingDetector.headline(rest.meetings.meetingApp) }
        if case let .video(app) = rest.hold { return "Watching in \(app)" }
        if rest.away { return "Away" }
        if rest.meetings.inMeeting { return MeetingDetector.headline(rest.meetings.meetingApp) }
        return "Working"
    }

    private var detail: String {
        if rest.isOnBreak { return "Esc twice to skip" }
        if let until = rest.pausedUntil { return "Until \(until.formatted(date: .omitted, time: .shortened))" }
        if rest.hold != nil { return "The break waits until it’s over" }
        if rest.away { return "The clock stops while you’re away" }
        return rest.nextIsLong ? "until a long break" : "until a short break"
    }
}

enum Clock {
    /// 12:04, or 0:30 for a short break.
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
