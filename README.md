# Rest

A small macOS menu bar break timer. The panel and the break screen are a flat grey landscape with something to look at standing on the horizon.

Every 20 minutes it covers the screen for 30 seconds, and every fourth break is 3 minutes. The break screen shows the time left and suggests something to look at out of the window, like a church spire or the top of a tree, each with its own pictogram. It follows the system's light or dark appearance. Breaks don't start while you're on a call or the app in front is playing video, and the clock stops while you're away.

## Controls

- The menu bar shows the minutes until the next break, dimmed while the clock is stopped, and the seconds left in a filled box during a break.
- The picture in the panel shows the time until the next break, with the thing to look at in the next break standing on the horizon.
- The round key pauses for an hour, or starts the clock again.
- Take a break now starts one straight away.
- In the last minute before a break, the notch widens to count down to it, like the Dynamic Island. Five seconds out it opens into the warning; its 5 more min key pushes the break back. On a Mac without a notch the warning is a white capsule under the menu bar instead, and clicking it does the same.
- For the last 10 seconds before a break, a small black disc follows the pointer with the seconds counting down in it. It doesn't take clicks, and near the edge of a screen it moves to the other side of the pointer.
- When a call starts, the notch opens with "On a call in Arc" next to the app's icon. Under it are two keys. Ignore till next break stops this call counting. Always ignore Arc stops Arc counting for good. It closes by itself after eight seconds unless the pointer is on it, and it doesn't open for the same app again within ten minutes. If an ignored app has the mic, click the call row in the panel to count it again. Shazam counts too, since it has the mic. Its notice reads "Shazam is active".
- Click the next-break row to push the break back five minutes.
- On the break screen, Skip or Esc twice ends it once the first five seconds are up. Until then Skip is filled in, and the fill shrinks from right to left.
- ⌘Q, or right-click anywhere in the panel, quits.

## Build

Needs macOS 14 or later, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Rest.xcodeproj -scheme Rest -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Rest.app
```

It's signed ad hoc, so a build only runs on the Mac that made it.

## How meeting detection works

- **Microphones.** CoreAudio lists every audio device. Rest keeps the ones with input streams and skips virtual and aggregate devices, because those run whenever their app is open, like Microsoft Teams Audio and Krisp. Teams' loopback driver is also matched by its UID. On each real mic it listens to `kAudioDevicePropertyDeviceIsRunningSomewhere`, which flips the moment any app opens it.
- **Which app.** On macOS 14.2 and later, CoreAudio has a list of processes. Rest asks each one which input devices it's using (`kAudioProcessPropertyDevices`), then names the app from its PID. Helpers are named after the app they're inside, so a Google Meet call shows as Google Chrome. Dictation apps like Wispr Flow and MacWhisper don't count as a call, and Voice Memos doesn't either. System daemons don't count, because `corespeechd` keeps the mic open for "Hey Siri". Only processes inside an app count, plus `avconferenced` (FaceTime) and WebKit's GPU process (calls in Safari).
- **Cameras.** The same running-somewhere flag through CoreMediaIO, skipping virtual cameras.
- **Video.** The app in front is playing video if it, or a helper inside it, is holding a display-sleep assertion (`IOPMCopyAssertionsByProcess`).
- **Away.** Seconds since the last input event, from `CGEventSource`. One minute stops the clock, and five minutes starts it over.

None of this records audio or video, so Rest doesn't ask for any permissions. The app isn't sandboxed, because naming other apps' processes needs `proc_pidpath`.

A break that comes due during a call starts 10 seconds after the call ends. A call that starts during a break ends the break.

## Settings

Apps you've chosen to always ignore are kept under `ignoredApps`; `defaults delete com.joeparkerrees.rest ignoredApps` clears the list.

All times are in seconds, through `defaults write com.joeparkerrees.rest <key> <value>`: `work` (1200), `shortBreak` (30), `longBreak` (180), `longEvery` (3), `pauseAfterIdle` (60), `resetAfterIdle` (300), `warning` (5), `skipLock` (5), `afterCall` (10), `cursor` (10, and 0 turns the pointer countdown off).

## Development

Debug builds take three flags.

- `--snapshot <folder>` renders the panel in five states, the break screen, the notch, the pointer countdown and every sight's pictogram offscreen, in light and dark, then quits.
- `--island` plays the notch live: twelve seconds of countdown, the warning opening at five and closing, then a call notice for Arc. The pointer countdown runs with it for the last ten seconds.
- `--meetings [seconds]` prints every input device it's watching or skipping, then once a second whether there's a call, which mic is live and which app has it. Open Voice Memos or join a call while it runs to see it change.

```sh
build/Build/Products/Debug/Rest.app/Contents/MacOS/Rest --meetings 30
```

## Files

- `MeetingDetector.swift` is the call detection: microphones, cameras and which app.
- `Activity.swift` reads idle time and the video check.
- `Rest.swift` is the clock and its rules.
- `Horizon.swift` is the panel's picture, `Panel.swift` everything around it, and `BreakScreen.swift` the break and the capsule warning.
- `Island.swift` is the countdown and warning that grow out of the notch.
- `Cursor.swift` is the countdown that follows the pointer.
- `Sights.swift` has the things to look at. Their pictograms are template PDFs under `Assets.xcassets/Sights`: eight traced from the pictogram set, and the spire, cloud, bird, crane and chimney drawn to match it. `tools/draw-sights.py <folder>` redraws those five (it needs Pillow and potrace).
- `Theme.swift` has the colours, the same greys and red as my [NTS app](https://github.com/joeparkerrees/nts), with a dark version of each.
