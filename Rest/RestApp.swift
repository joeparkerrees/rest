import SwiftUI

@main
struct RestApp: App {
    @State private var rest: Rest

    init() {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            Snapshot.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        if CommandLine.arguments.contains("--island") {
            IslandDemo.run()
            _rest = State(initialValue: Rest(defaults: UserDefaults(suiteName: "selftest")!))
            return
        }
        if CommandLine.arguments.contains("--meetings") {
            let rest = Rest(defaults: UserDefaults(suiteName: "selftest")!)
            MeetingSelfTest.run(rest.meetings)
            _rest = State(initialValue: rest)
            return
        }
        #endif
        let rest = Rest()
        rest.start()
        _rest = State(initialValue: rest)
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(rest: rest)
        } label: {
            Image(nsImage: MenuBarIcon.image(text: iconText, dimmed: iconDimmed))
                .accessibilityLabel(rest.isOnBreak ? "Rest, on a break" : "Rest, \(Clock.format(rest.remaining)) until a break")
        }
        .menuBarExtraStyle(.window)
    }

    /// Beside the mark: the minutes until the break, rounded up so it reads
    /// 1m right up to the break; "On a call" while one is on, or just
    /// "Shazam" while it listens; the time left during a break.
    private var iconText: String {
        if rest.isOnBreak { return Clock.format(rest.breakRemaining) }
        if rest.isPaused { return "Paused" }
        if rest.meetings.inMeeting {
            if let app = rest.meetings.meetingApp, MeetingDetector.listeners.contains(app.key) { return app.name }
            return "On a call"
        }
        if case .video = rest.hold { return "Watching" }
        return "\(Int((rest.remaining / 60).rounded(.up)))m"
    }

    /// Greyed while the clock is stopped and nothing else explains it.
    private var iconDimmed: Bool {
        !rest.isOnBreak && (rest.isPaused || (rest.away && !rest.meetings.inMeeting))
    }
}
