import SwiftUI

/// The panel's picture: a pale sky over the land, with the sight for your
/// next break standing on the horizon. The sun comes up from behind the land
/// as the minutes of work go by, and it's at the top when the break is due.
/// During a break it goes back down. It goes hollow while the clock is
/// stopped: paused, away, or holding a break for a call. The time sits in
/// the sky on the left.
struct HorizonScene: View {
    let rest: Rest
    var width: CGFloat = Theme.panelWidth - Theme.gutter * 2

    static let height: CGFloat = 184
    static let land: CGFloat = 46
    static let sunSize: CGFloat = 18
    /// The sun's centre at noon, from the top of the picture.
    static let noon: CGFloat = 26

    private var horizon: CGFloat { Self.height - Self.land }

    /// The clock isn't moving: paused, away, or a break waiting on a call.
    private var stopped: Bool {
        rest.isPaused || rest.away || rest.hold != nil
    }

    /// Down from the top: just under the horizon at the start of the work,
    /// noon when the break is due, and back under by the end of the break.
    private var sunY: CGFloat {
        let below = horizon + Self.sunSize / 2 + 1
        let height = rest.isOnBreak ? rest.progress : 1 - rest.progress
        return Self.noon + (below - Self.noon) * height
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.sky
            Sun(size: Self.sunSize, hollow: stopped)
                .position(x: width - 46, y: sunY)
                // One second of travel per tick reads as steady; a reset at
                // the end of a break should jump, not sweep.
                .animation(rest.progress > 0.002 ? .linear(duration: 1) : nil, value: sunY)
                .animation(.easeOut(duration: 0.2), value: stopped)
            Theme.land
                .frame(height: Self.land)
                .frame(maxHeight: .infinity, alignment: .bottom)
            SightFigure(sight: rest.nextSight, size: 30)
                .position(x: width - 110, y: horizon - 15)
            Readout(rest: rest)
                .frame(width: width - 76, alignment: .leading)
                .padding(.leading, 16)
                .padding(.top, 18)
        }
        .frame(width: width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        // At night the land is darker than the haze, so a hairline keeps
        // the picture's edge.
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The red sun: solid while the clock runs, a ring while it's stopped.
struct Sun: View {
    var size: CGFloat
    var hollow = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.red).opacity(hollow ? 0 : 1)
            Circle().strokeBorder(Theme.red, lineWidth: max(1.5, size / 12)).opacity(hollow ? 1 : 0)
        }
        .frame(width: size, height: size)
    }
}

/// The sky's text: what's happening, the time left, and what it's counting to.
private struct Readout: View {
    let rest: Rest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                // An on-air light: only while a call has the mic.
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
        .fixedSize(horizontal: false, vertical: true)
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
