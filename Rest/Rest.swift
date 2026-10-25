import AppKit
import Observation
import ServiceManagement

/// The work and break clock. By default that's 20 minutes of work, a
/// 30-second break, and a 3-minute break after every third short one. It stops counting after a minute away and starts over after five.
/// A break that comes due during a call, or while the app in front is playing
/// video, waits until it's over. Every 10 minutes of work there's a reminder
/// out of the notch to sit up straight.
@MainActor
@Observable
final class Rest {
    enum Phase: Equatable {
        case working
        /// The short warning before a break.
        case warning(until: Date)
        case onBreak(long: Bool, started: Date, ends: Date)
    }

    /// Why a due break hasn't started.
    enum Hold: Equatable {
        case call(String?)
        case video(String)
    }

    struct Settings {
        var work: TimeInterval
        var shortBreak: TimeInterval
        var longBreak: TimeInterval
        var longEvery: Int
        var pauseAfterIdle: TimeInterval
        var resetAfterIdle: TimeInterval
        var warning: TimeInterval
        var skipLock: TimeInterval
        /// How long after a call ends before its held break starts.
        var afterCall: TimeInterval
        /// How long before a break the countdown shows by the pointer; 0 turns it off.
        var cursor: TimeInterval
        /// How much work between posture reminders.
        var posture: TimeInterval

        /// Override any of them with `defaults write com.joeparkerrees.rest <key> <seconds>`.
        init(_ defaults: UserDefaults) {
            func seconds(_ key: String, _ fallback: TimeInterval) -> TimeInterval {
                let value = defaults.double(forKey: key)
                return value > 0 ? value : fallback
            }
            work = seconds("work", 20 * 60)
            shortBreak = seconds("shortBreak", 30)
            longBreak = seconds("longBreak", 3 * 60)
            longEvery = max(1, Int(seconds("longEvery", 3)))
            pauseAfterIdle = seconds("pauseAfterIdle", 60)
            resetAfterIdle = seconds("resetAfterIdle", 5 * 60)
            warning = seconds("warning", 5)
            skipLock = seconds("skipLock", 5)
            afterCall = seconds("afterCall", 10)
            cursor = defaults.object(forKey: "cursor") == nil ? 10 : max(0, defaults.double(forKey: "cursor"))
            posture = seconds("posture", 10 * 60)
        }
    }

    private(set) var phase: Phase = .working
    /// Seconds worked since the last break.
    private(set) var worked: TimeInterval = 0
    /// Short breaks taken since the last long one.
    private(set) var shortsSinceLong = 0
    private(set) var away = false
    private(set) var hold: Hold?
    private(set) var pausedUntil: Date?
    /// Ticks once a second, so views reading `now` stay current.
    private(set) var now = Date()
    /// Apps you've told Rest never to count as a call, by bundle ID.
    private(set) var ignoredApps: [String] = []
    /// What the next break will suggest looking at. It stands on the
    /// horizon in the panel until then.
    private(set) var nextSight = Sight.pick(after: nil)
    /// Turned on and off from the panel's footer.
    var postureReminders: Bool {
        didSet { defaults.set(postureReminders, forKey: "postureReminders") }
    }

    let settings: Settings
    let meetings = MeetingDetector()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var callEndedAt: Date?
    /// The call the notice last spoke about, and when each was announced.
    @ObservationIgnored private var currentCall: String?
    @ObservationIgnored private var announced: [String: Date] = [:]
    @ObservationIgnored private let breakWindows = BreakWindows()
    @ObservationIgnored private let island = Island()
    @ObservationIgnored private let cursor = CursorCountdown()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Settings(defaults)
        ignoredApps = defaults.stringArray(forKey: "ignoredApps") ?? []
        postureReminders = defaults.object(forKey: "postureReminders") == nil ? true : defaults.bool(forKey: "postureReminders")
        meetings.excludedBundleIDs.formUnion(ignoredApps)
    }

    func start() {
        meetings.start()
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.2
        // Waking from sleep is a break in itself.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetClock() }
        }
    }

    // MARK: Reading

    var nextIsLong: Bool { shortsSinceLong >= settings.longEvery }
    var remaining: TimeInterval { max(0, settings.work - worked) }
    var isPaused: Bool { pausedUntil != nil }
    var isOnBreak: Bool { if case .onBreak = phase { true } else { false } }

    /// How far round the dial the bead is: through the work, or through the break.
    var progress: Double {
        switch phase {
        case .working, .warning: min(1, worked / settings.work)
        case let .onBreak(_, started, ends): min(1, max(0, now.timeIntervalSince(started) / ends.timeIntervalSince(started)))
        }
    }

    var breakRemaining: TimeInterval {
        if case let .onBreak(_, _, ends) = phase { return max(0, ends.timeIntervalSince(now)) }
        return 0
    }

    /// Seconds until Skip works. Read from the clock, not the last tick, so
    /// Skip unlocks the moment its fill runs out.
    var skipLockLeft: TimeInterval {
        if case let .onBreak(_, started, _) = phase { return max(0, settings.skipLock - Date().timeIntervalSince(started)) }
        return 0
    }

    var canSkip: Bool { skipLockLeft == 0 }

    // MARK: Actions

    func breakNow() {
        island.hideCountdown()
        beginBreak()
    }

    func skip() {
        guard isOnBreak, canSkip else { return }
        endBreak()
    }

    /// Pushes the coming break back, from the warning or the panel.
    func postpone(_ seconds: TimeInterval = 5 * 60) {
        island.hideCountdown()
        cursor.hide()
        phase = .working
        worked = max(0, settings.work - seconds)
    }

    func togglePause() {
        if isPaused { resume() } else { pause(for: 60 * 60) }
    }

    func pause(for seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
        island.hideCountdown()
        cursor.hide()
        island.hideNotice()
        if case .warning = phase { phase = .working }
    }

    func resume() {
        pausedUntil = nil
        lastTick = Date()
    }

    /// From the call notice: this call stops counting until the next break.
    func ignoreCallUntilBreak() {
        meetings.ignoreUntilBreak()
        island.hideNotice()
    }

    /// From the call notice: the app never counts as a call again, until it's
    /// let back in from the panel.
    func alwaysIgnore(_ app: MeetingDetector.App) {
        if !ignoredApps.contains(app.key) { ignoredApps.append(app.key) }
        defaults.set(ignoredApps, forKey: "ignoredApps")
        meetings.excludedBundleIDs.insert(app.key)
        // The camera, if it's on, still counts until the next break otherwise.
        meetings.ignoreUntilBreak()
        island.hideNotice()
    }

    func countAsCall(_ app: MeetingDetector.App) {
        ignoredApps.removeAll { $0 == app.key }
        defaults.set(ignoredApps, forKey: "ignoredApps")
        meetings.excludedBundleIDs.remove(app.key)
    }

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    // MARK: Clock

    private func tick() {
        defer { updateCursor() }
        let current = Date()
        // A long gap means the Mac slept or the app was stalled; don't count it as work.
        let delta = min(current.timeIntervalSince(lastTick), 5)
        lastTick = current
        now = current
        let idle = Activity.idleSeconds
        if !isPaused { announceCall() }

        switch phase {
        case .working:
            if let pausedUntil {
                guard current >= pausedUntil else { return }
                resume()
            }
            if idle >= settings.resetAfterIdle {
                resetClock()
                return
            }
            away = idle >= settings.pauseAfterIdle
            if !away {
                let before = worked
                worked = min(settings.work, worked + delta)
                if Int(worked / settings.posture) > Int(before / settings.posture) { remindPosture() }
            }

            guard worked >= settings.work, !away else {
                hold = nil
                // The last minute counts down beside the notch. It counts to
                // the break itself, so the warning carries straight on from it.
                let untilBreak = remaining + settings.warning
                if !away, !meetings.inMeeting, untilBreak <= 60 { island.approach(remaining: untilBreak) } else { island.hideCountdown() }
                return
            }
            hold = currentHold()
            if meetings.inMeeting { callEndedAt = nil }
            if hold != nil { island.hideCountdown() }
            if hold == nil {
                // Give a call a moment to finish before the break lands on it.
                if let ended = callEndedAt, current.timeIntervalSince(ended) < settings.afterCall { return }
                startWarning()
            }

        case let .warning(until):
            if let held = currentHold() {
                hold = held
                island.hideCountdown()
                phase = .working
            } else if current >= until {
                island.hideCountdown()
                beginBreak()
            } else {
                island.update(seconds: Int(until.timeIntervalSince(current).rounded(.up)))
            }

        case let .onBreak(_, _, ends):
            // A call coming in ends the break rather than covering it.
            if meetings.inMeeting {
                endBreak()
            } else if current >= ends {
                endBreak()
            }
        }
    }

    /// When a call starts, the island says so, with a way out if it isn't a
    /// call. Once per app in ten minutes,
    /// so a dropped call that rejoins doesn't ask again.
    private func announceCall() {
        let key: String? = meetings.inMeeting ? (meetings.meetingApp?.key ?? "camera") : nil
        guard key != currentCall else { return }
        currentCall = key
        guard let key else {
            island.hideNotice()
            return
        }
        if let last = announced[key], now.timeIntervalSince(last) < 10 * 60 { return }
        announced[key] = now
        let app = meetings.meetingApp
        island.notice(.init(
            title: app.map(MeetingDetector.headline) ?? (meetings.cameraRunning ? "Your camera is on" : "On a call"),
            name: app?.name,
            icon: app?.bundleID.flatMap { Island.icon(bundleID: $0) },
            ignore: { [weak self] in self?.ignoreCallUntilBreak() },
            always: app.map { app in { [weak self] in self?.alwaysIgnore(app) } }
        ))
    }

    /// Sit up straight, out of the notch. Only while you're working with
    /// nothing else on: not on a call, not with video in front, and not in
    /// the last minute, when the notch is counting down to the break.
    private func remindPosture() {
        guard postureReminders, hold == nil, !meetings.inMeeting, remaining + settings.warning > 60,
              Activity.videoInFront() == nil else { return }
        island.posture()
    }

    /// The countdown by the pointer, for the last few seconds before a break
    /// that's going to start: not while the clock's stopped, and not when a
    /// call or video in front will hold it.
    private func updateCursor() {
        let left: TimeInterval? = switch phase {
        case .working where !isPaused && !away && hold == nil && !meetings.inMeeting && worked < settings.work:
            remaining + settings.warning
        case let .warning(until):
            max(0, until.timeIntervalSince(now))
        default:
            nil
        }
        guard let left, settings.cursor > 0, left <= settings.cursor, left > 0,
              phase != .working || Activity.videoInFront() == nil else {
            cursor.hide()
            return
        }
        cursor.show(until: now.addingTimeInterval(left))
    }

    private func currentHold() -> Hold? {
        if meetings.inMeeting {
            return .call(meetings.meetingApp?.name)
        }
        if hold.map({ if case .call = $0 { true } else { false } }) == true {
            callEndedAt = Date()
        }
        if let app = Activity.videoInFront() { return .video(app) }
        return nil
    }

    private func startWarning() {
        let until = Date().addingTimeInterval(settings.warning)
        phase = .warning(until: until)
        let long = nextIsLong
        island.warn(seconds: Int(settings.warning), long: long, length: long ? settings.longBreak : settings.shortBreak) { [weak self] in
            self?.postpone()
        }
    }

    private func beginBreak() {
        let long = nextIsLong
        shortsSinceLong = long ? 0 : shortsSinceLong + 1
        let started = Date()
        now = started
        phase = .onBreak(long: long, started: started, ends: started.addingTimeInterval(long ? settings.longBreak : settings.shortBreak))
        hold = nil
        cursor.hide()
        breakWindows.show(rest: self, sight: nextSight)
    }

    private func endBreak() {
        breakWindows.hide()
        nextSight = Sight.pick(after: nextSight)
        phase = .working
        worked = 0
        lastTick = Date()
        meetings.clearIgnored()
    }

    private func resetClock() {
        worked = 0
        shortsSinceLong = 0
        hold = nil
        away = false
        meetings.clearIgnored()
        island.hideCountdown()
        cursor.hide()
        if case .warning = phase { phase = .working }
    }

    #if DEBUG
    /// Snapshots set the clock directly instead of waiting for it.
    func seedForSnapshot(worked: TimeInterval, away: Bool = false, hold: Hold? = nil, paused: Bool = false, onBreak: (long: Bool, elapsed: TimeInterval)? = nil, sight: Sight = Sight.all[0]) {
        self.worked = worked
        nextSight = sight
        self.away = away
        self.hold = hold
        pausedUntil = paused ? Date().addingTimeInterval(3600) : nil
        if let onBreak {
            let started = Date().addingTimeInterval(-onBreak.elapsed)
            phase = .onBreak(long: onBreak.long, started: started, ends: started.addingTimeInterval(onBreak.long ? settings.longBreak : settings.shortBreak))
        }
        now = Date()
    }
    #endif
}
