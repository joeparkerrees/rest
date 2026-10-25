#if DEBUG
import AppKit
import CoreAudio
import SwiftUI

/// `Rest --snapshot <dir> [image]` renders the panel in a few states and the
/// break screen offscreen, and exits, so the UI can be checked without
/// waiting twenty minutes.
@MainActor
enum Snapshot {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "snapshot")!
        defaults.removePersistentDomain(forName: "snapshot")

        let mic = "MacBook Pro Microphone"
        let zoom = MeetingDetector.App(name: "Zoom", bundleID: "us.zoom.xos", isSystem: false)
        let states: [(String, (Rest) -> Void)] = [
            ("working", { $0.seedForSnapshot(worked: 7 * 60 + 26) }),
            ("call", { $0.meetings.seedForSnapshot(microphone: mic, callIn: zoom); $0.seedForSnapshot(worked: 20 * 60, hold: .call("Zoom")) }),
            ("away", { $0.seedForSnapshot(worked: 13 * 60, away: true) }),
            ("paused", { $0.seedForSnapshot(worked: 4 * 60, paused: true) }),
            // A sight that flies instead of standing.
            ("plane", { $0.seedForSnapshot(worked: 19 * 60 + 30, sight: Sight.all[4]) }),
        ]
        for (name, seed) in states {
            let rest = Rest(defaults: defaults)
            rest.meetings.seedForSnapshot(microphone: mic)
            seed(rest)
            write(Panel(rest: rest).fixedSize(), to: directory.appendingPathComponent("panel-\(name).png"))
            write(Panel(rest: rest).fixedSize(), to: directory.appendingPathComponent("panel-\(name)-dark.png"), scheme: .dark)
        }

        let rest = Rest(defaults: defaults)
        rest.seedForSnapshot(worked: 0, onBreak: (long: false, elapsed: 9))
        write(BreakScreen(rest: rest, sight: Sight.all[0]).frame(width: 1440, height: 900), to: directory.appendingPathComponent("break.png"), scale: 1)
        write(BreakScreen(rest: rest, sight: Sight.all[1]).frame(width: 1440, height: 900), to: directory.appendingPathComponent("break-dark.png"), scale: 1, scheme: .dark)
        // A sight that flies rather than stands.
        write(BreakScreen(rest: rest, sight: Sight.all[4]).frame(width: 1440, height: 900), to: directory.appendingPathComponent("break-plane.png"), scale: 1)

        // Skip part way through its lock, at 2x.
        let skips = HStack(spacing: 16) {
            ForEach([1, 0.6, 0.25, 0], id: \.self) { fill in
                Button {} label: { Text("Skip").frame(minWidth: 88, minHeight: 30) }
                    .buttonStyle(LandKey(fill: fill))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink.opacity(fill > 0 ? 0.55 : 1))
            }
        }
        .padding(24)
        write(skips.background(Theme.land), to: directory.appendingPathComponent("skip.png"))
        write(skips.background(Theme.land), to: directory.appendingPathComponent("skip-dark.png"), scheme: .dark)

        // Every suggestion's icon, in a row, at 2x.
        let icons = HStack(spacing: 24) {
            ForEach(Sight.all.indices, id: \.self) { index in
                SightIcon(icon: Sight.all[index].icon)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(24)
        write(icons.background(Theme.paper), to: directory.appendingPathComponent("sights.png"))
        write(icons.background(Theme.paper), to: directory.appendingPathComponent("sights-dark.png"), scheme: .dark)

        renderIsland(to: directory)
        renderCursor(to: directory)
        for mark in MenuBarIcon.Mark.allCases {
            for (name, text, dimmed) in [("12m", "12m", false), ("call", "On a call", false), ("break", "0:24", false), ("paused", "Paused", true)] {
                let icon = MenuBarIcon.image(text: text, dimmed: dimmed, mark: mark)
                icon.size = NSSize(width: icon.size.width * 4, height: icon.size.height * 4)
                if let tiff = icon.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appendingPathComponent("menubar-\(mark)-\(name).png"))
                }
            }
        }
    }

    /// The island in each state, over a mock of the menu bar and notch.
    static func renderIsland(to directory: URL) {
        let arc = Island.Call(title: "On a call in Arc", name: "Arc", icon: Island.icon(bundleID: "company.thebrowser.Browser"), ignore: {}, always: {})
        let shazam = Island.Call(title: "Shazam is active", name: "Shazam", icon: Island.icon(bundleID: "com.shazam.mac.Shazam"), ignore: {}, always: {})
        for (name, mode, content, remaining, call) in [("island-compact", IslandModel.Mode.compact, IslandModel.Content.countdown, 42.0, arc),
                                                       ("island-expanded", .expanded, .countdown, 5.0, arc), ("island-call", .expanded, .call, 0, arc),
                                                       ("island-shazam", .expanded, .call, 0, shazam), ("island-posture", .expanded, .posture, 0, arc)] {
            let model = IslandModel()
            model.notch = CGSize(width: 185, height: 32)
            model.mode = mode
            model.content = content
            model.call = call
            model.remaining = remaining
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x8C9BAA), Color(hex: 0xC9C2B6)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.55)).frame(height: 32)
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 185, height: 32)
                IslandView(model: model).frame(width: model.windowSize.width, height: model.windowSize.height)
            }
            .frame(width: 560, height: 150)
            write(view, to: directory.appendingPathComponent("\(name).png"))
        }
        // Without a notch, the posture reminder's capsule.
        let capsule = PosturePill().padding(20)
        write(capsule.background(Theme.ground), to: directory.appendingPathComponent("posture-capsule.png"))
        write(capsule.background(Theme.ground), to: directory.appendingPathComponent("posture-capsule-dark.png"), scheme: .dark)
    }

    /// The countdown by the pointer, seven seconds out, beside the arrow.
    static func renderCursor(to directory: URL) {
        let pointer = CGPoint(x: 28, y: 22)
        let view = ZStack(alignment: .topLeading) {
            Theme.ground
            CursorDial(seconds: 7)
                .offset(x: pointer.x + CursorCountdown.offset - CursorCountdown.size / 2, y: pointer.y + CursorCountdown.offset - CursorCountdown.size / 2)
            // Offscreen there's no cursor image to draw, so a stand-in arrow
            // with its hotspot on the pointer.
            Arrow().fill(.black).overlay(Arrow().stroke(.white, lineWidth: 1.5))
                .frame(width: 12, height: 19)
                .offset(x: pointer.x, y: pointer.y)
        }
        .frame(width: 120, height: 100, alignment: .topLeading)
        write(view, to: directory.appendingPathComponent("cursor.png"))
        write(view, to: directory.appendingPathComponent("cursor-dark.png"), scheme: .dark)

        // Where it sits in each corner of a 1440 by 900 screen.
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        for point in [NSPoint(x: 700, y: 450), NSPoint(x: 1430, y: 450), NSPoint(x: 700, y: 10), NSPoint(x: 1430, y: 10)] {
            print("pointer", point, "dial centre", CursorCountdown.centre(for: point, in: screen))
        }
    }

    private struct Arrow: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 16), CGPoint(x: 4, y: 12.5), CGPoint(x: 7, y: 19),
                               CGPoint(x: 9.5, y: 18), CGPoint(x: 6.5, y: 11.5), CGPoint(x: 11.5, y: 11.5)])
                path.closeSubpath()
            }
        }
    }

    private static func write(_ view: some View, to url: URL, scale: CGFloat = 2, scheme: ColorScheme = .light) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

/// `Rest --island` plays the island live over the notch: twelve seconds of
/// countdown, the warning opening at five, then closing back into the notch.
/// The countdown by the pointer runs with it for the last ten seconds. Then
/// the posture reminder, and a call notice.
@MainActor
enum IslandDemo {
    static func run() {
        let island = Island()
        let cursor = CursorCountdown()
        Task {
            try? await Task.sleep(for: .seconds(1))
            // The pointer's countdown runs alongside, for the last ten seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MainActor.assumeIsolated { cursor.show(until: Date().addingTimeInterval(10)) }
            }
            for second in stride(from: 12, through: 6, by: -1) {
                island.approach(remaining: TimeInterval(second))
                try? await Task.sleep(for: .seconds(1))
            }
            if let screen = NSScreen.main, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
               let window = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).contains("IslandPanel") }) {
                print("notch x \(left.maxX)–\(right.minX), top \(screen.frame.maxY) | island window x \(window.frame.minX)–\(window.frame.maxX), top \(window.frame.maxY), height \(window.frame.height), mid \(window.frame.midX) vs \((left.maxX + right.minX) / 2)")
            }
            island.warn(seconds: 5, long: false, length: 30) { print("5 more min") }
            for second in stride(from: 4, through: 1, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                island.update(seconds: second)
            }
            try? await Task.sleep(for: .seconds(1))
            island.hideCountdown()
            cursor.hide()
            try? await Task.sleep(for: .seconds(1.5))
            // The posture reminder, which closes by itself after six seconds.
            island.posture()
            try? await Task.sleep(for: .seconds(8))
            // Then a call starting in Arc; it closes by itself after eight seconds.
            island.notice(.init(title: "On a call in Arc", name: "Arc", icon: Island.icon(bundleID: "company.thebrowser.Browser"),
                                ignore: { print("ignore till next break"); island.hideNotice() },
                                always: { print("always ignore Arc"); island.hideNotice() }))
            try? await Task.sleep(for: .seconds(10))
            exit(0)
        }
    }
}

/// `Rest --meetings [seconds]` prints what the meeting detector sees once a
/// second: every real microphone, whether it's running, who has it, and the
/// camera. Join a call or open Voice Memos while it runs to watch it change.
@MainActor
enum MeetingSelfTest {
    static func run(_ meetings: MeetingDetector) {
        let seconds = CommandLine.arguments.last.flatMap(Int.init) ?? 20
        meetings.start()
        // Every input device, and why the skipped ones are skipped.
        for id in Audio.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) where Audio.hasInput(id) {
            let name = Audio.string(id, kAudioObjectPropertyName) ?? "?"
            print(Audio.isVirtual(id) ? "skipped" : "watching", "·", name, "· transport", Audio.transportName(id))
        }
        Task {
            for second in 0..<seconds {
                let mics = meetings.microphones.map { "\($0.name)\($0.running ? " [LIVE]" : "")" }.joined(separator: ", ")
                let apps = meetings.micApps.map { "\($0.name) (\($0.bundleID ?? "?"))\(meetings.countsAsCall($0) ? "" : $0.isSystem ? " [system, ignored]" : " [excluded]")" }.joined(separator: ", ")
                print(String(format: "%2ds", second), "call:", meetings.inMeeting ? "YES" : "no ",
                      "| mics:", mics.isEmpty ? "none" : mics,
                      "| on the mic:", apps.isEmpty ? "-" : apps,
                      "| camera:", meetings.cameraRunning ? "on" : "off")
                fflush(stdout)
                try? await Task.sleep(for: .seconds(1))
            }
            exit(0)
        }
    }
}
#endif
