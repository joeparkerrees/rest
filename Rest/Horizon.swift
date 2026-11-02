import SwiftUI

/// The top of the panel: the time, with the sight for your next break standing
/// on the line under it, or up in the sky over it if it flies.
struct HorizonScene: View {
    let rest: Rest

    static let height: CGFloat = 110
    static let figure: CGFloat = 62
    static let margin: CGFloat = 16

    var body: some View {
        ZStack(alignment: .topLeading) {
            SightFigure(sight: rest.nextSight, size: Self.figure)
                .position(x: Theme.panelWidth - Self.margin - Self.figure / 2, y: Self.height - Self.figure / 2)
            Readout(rest: rest)
                .padding(.leading, Self.margin)
                .padding(.trailing, Self.margin + Self.figure)
                .padding(.top, 14)
        }
        .frame(width: Theme.panelWidth, height: Self.height, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

/// What's happening, and the time left.
private struct Readout: View {
    let rest: Rest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                // An on-air light: only while a call has the mic.
                if rest.meetings.inMeeting {
                    Circle().fill(Theme.red).frame(width: 5, height: 5)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(status)
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .animation(Theme.settle, value: status)

            Text(Clock.format(shown))
                .font(.system(size: 46, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .fixedSize()
                // Takes its direction from the value, so pushing a break back rolls up.
                .contentTransition(.numericText(value: shown))
                .animation(.easeOut(duration: 0.2), value: Int(shown))
        }
    }

    private var shown: TimeInterval {
        rest.isOnBreak ? rest.breakRemaining : rest.remaining
    }

    private var status: String {
        if rest.isOnBreak { return "On a break. Esc twice to skip" }
        if let until = rest.pausedUntil { return "Paused until \(until.formatted(date: .omitted, time: .shortened))" }
        if rest.isPaused { return "Paused" }
        if case .call = rest.hold { return MeetingDetector.headline(rest.meetings.meetingApp) }
        if case let .video(app) = rest.hold { return "Watching in \(app)" }
        if rest.away { return "Away" }
        if rest.meetings.inMeeting { return MeetingDetector.headline(rest.meetings.meetingApp) }
        return "Working"
    }
}

enum Clock {
    /// 12:04, or 0:30 for a short break.
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
