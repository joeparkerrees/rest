import AppKit
import IOKit.pwr_mgt

/// Whether you're at the Mac, and whether the app in front is playing video.
enum Activity {
    /// Seconds since the last key, click, scroll or mouse move in any app.
    /// Reading it needs no permission, unlike watching the events themselves.
    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// The app in front, if it's keeping the display awake: what a video
    /// player or a browser playing video does. Browsers hold the assertion
    /// from a helper process inside their bundle, so a helper counts for its
    /// app. Only the app in front counts, so a video left playing behind your
    /// work doesn't hold breaks back.
    static func videoInFront() -> String? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let appPath = front.bundleURL?.path
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as NSDictionary? else { return nil }

        let keepsDisplayAwake: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        for (key, value) in byProcess {
            guard let pid = (key as? NSNumber)?.int32Value,
                  let assertions = value as? [[String: Any]],
                  assertions.contains(where: { keepsDisplayAwake.contains($0[kIOPMAssertionTypeKey] as? String ?? "") })
            else { continue }
            if pid == front.processIdentifier { return front.localizedName }
            if let appPath, let path = Processes.path(pid), path.hasPrefix(appPath + "/") { return front.localizedName }
        }
        return nil
    }
}
