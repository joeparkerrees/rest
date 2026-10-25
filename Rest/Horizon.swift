import SwiftUI

/// The panel's picture: a pale sky over the land, with the sight for your
/// next break standing on the horizon. The time sits in the sky on the left.
struct HorizonScene: View {
    let rest: Rest
    var width: CGFloat = Theme.panelWidth - Theme.gutter * 2

    static let height: CGFloat = 184
    static let land: CGFloat = 46
    static let figure: CGFloat = 52
    /// The sight's centre, this far in from the right.
    static let inset: CGFloat = 58

    private var horizon: CGFloat { Self.height - Self.land }

    var body: some View {
        let centre = width - Self.inset
        return ZStack(alignment: .topLeading) {
            Theme.sky
            Theme.land
                .frame(height: Self.land)
                .frame(maxHeight: .infinity, alignment: .bottom)
            SightFigure(sight: rest.nextSight, size: Self.figure)
                .position(x: centre, y: horizon - Self.figure / 2)
            // Kept clear of the sight, so the longer lines wrap.
            Readout(rest: rest)
                .frame(width: centre - Self.figure / 2 - 24, alignment: .leading)
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
        if case .call = rest.hold { return "The break starts after the call" }
        if case .video = rest.hold { return "The break starts after the video" }
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
