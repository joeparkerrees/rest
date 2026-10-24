import AppKit
import CoreAudio
import CoreMediaIO
import Observation

/// Is a call on? It reads these signals:
///
/// - Every real microphone's "running somewhere" flag, with a listener on
///   each one, so it flips the moment any app opens the mic. Virtual and
///   aggregate devices (Teams' loopback, Krisp, BlackHole) are skipped, because
///   they run whenever their app is open.
/// - On macOS 14.2 and later, CoreAudio's process list says which app has the
///   mic, so dictation tools can be left out and the panel can name the call.
/// - The same "running somewhere" flag on every real camera.
///
/// Nothing here records audio or video, so it needs no microphone or camera
/// permission.
@MainActor
@Observable
final class MeetingDetector {
    struct Microphone: Identifiable, Equatable {
        let id: AudioObjectID
        let uid: String
        let name: String
        var running: Bool
    }

    struct App: Equatable {
        let name: String
        let bundleID: String?
        /// A system daemon rather than an app: Siri and dictation (corespeechd),
        /// Voice Control and the like. They hold the mic without being a call.
        let isSystem: Bool

        /// What ignoring is keyed on: the bundle ID, or the name without one.
        var key: String { bundleID ?? name }
    }

    private(set) var microphones: [Microphone] = []
    private(set) var cameraRunning = false
    /// Apps using a live microphone, outermost app first (Chrome, not its helper).
    private(set) var micApps: [App] = []
    /// Whether CoreAudio can say who has the mic (macOS 14.2 and later).
    private(set) var canAttribute = false

    /// Apps that use the mic without being on a call.
    var excludedBundleIDs: Set<String> = MeetingDetector.defaultExclusions
    var watchesCamera = true
    /// Apps waved off from the call notice, until the next break.
    private(set) var ignoredUntilBreak: Set<String> = []
    private(set) var ignoresCameraUntilBreak = false

    static let defaultExclusions: Set<String> = [
        "com.electron.wispr-flow",       // Wispr Flow
        "com.superduper.superwhisper",   // superwhisper
        "com.goodsnooze.MacWhisper",     // MacWhisper
        "com.apple.VoiceMemos",
    ]

    /// Apps that listen without being on a call. They hold the break like a
    /// call, but Rest says they're active rather than on a call.
    static let listeners: Set<String> = ["com.shazam.mac.Shazam"]

    /// "On a call in Arc", or "Shazam is active".
    static func headline(_ app: App?) -> String {
        guard let app else { return "On a call" }
        return listeners.contains(app.key) ? "\(app.name) is active" : "On a call in \(app.name)"
    }

    /// A call is on when a mic is live and an app using it counts as a call:
    /// a real app, not excluded. System daemons like corespeechd, which keeps
    /// the mic open for "Hey Siri", never count. If CoreAudio can't say who
    /// has the mic at all, a live mic counts.
    var inMeeting: Bool {
        if microphones.contains(where: \.running) {
            if !canAttribute || micApps.contains(where: countsAsCall) { return true }
        }
        return watchesCamera && cameraRunning && !ignoresCameraUntilBreak
    }

    /// What to call the meeting in the panel.
    var meetingApp: App? {
        micApps.first(where: countsAsCall)
    }

    func countsAsCall(_ app: App) -> Bool {
        !app.isSystem && !excludedBundleIDs.contains(app.key) && !ignoredUntilBreak.contains(app.key)
    }

    /// "Ignore till next break": whatever counts as a call right now stops
    /// counting, the camera included if it's on.
    func ignoreUntilBreak() {
        ignoredUntilBreak.formUnion(micApps.filter(countsAsCall).map(\.key))
        if cameraRunning { ignoresCameraUntilBreak = true }
    }

    func clearIgnored() {
        ignoredUntilBreak = []
        ignoresCameraUntilBreak = false
    }

    @ObservationIgnored private var micListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    @ObservationIgnored private var cameraListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    @ObservationIgnored private var cameras: [CMIOObjectID] = []
    @ObservationIgnored private var devicesListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var cameraDevicesListener: CMIOObjectPropertyListenerBlock?
    /// While a mic is live the app using it can change (a second call, a
    /// dictation burst), so attribution is rechecked on a slow beat.
    @ObservationIgnored private var attributionTimer: Timer?

    func start() {
        reloadMicrophones()
        reloadCameras()

        var devices = Audio.address(kAudioHardwarePropertyDevices)
        let devicesChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reloadMicrophones() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main, devicesChanged)
        devicesListener = devicesChanged

        var cameraDevices = Video.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let camerasChanged: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reloadCameras() }
        }
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraDevices, .main, camerasChanged)
        cameraDevicesListener = camerasChanged
    }

    #if DEBUG
    /// Snapshots set what the detector sees instead of reading the hardware:
    /// one microphone, live if an app has it for a call.
    func seedForSnapshot(microphone: String, callIn app: App? = nil) {
        microphones = [Microphone(id: 0, uid: "snapshot", name: microphone, running: app != nil)]
        micApps = app.map { [$0] } ?? []
        canAttribute = true
    }
    #endif

    // MARK: Microphones

    private func reloadMicrophones() {
        let found = Audio.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap { id -> Microphone? in
            guard Audio.hasInput(id), !Audio.isVirtual(id) else { return nil }
            return Microphone(
                id: id,
                uid: Audio.string(id, kAudioDevicePropertyDeviceUID) ?? "",
                name: Audio.string(id, kAudioObjectPropertyName) ?? "Microphone",
                running: Audio.isRunningSomewhere(id)
            )
        }

        var address = Audio.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        for (id, block) in micListeners where !found.contains(where: { $0.id == id }) {
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
            micListeners[id] = nil
        }
        for mic in found where micListeners[mic.id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.micRunningChanged() }
            }
            if AudioObjectAddPropertyListenerBlock(mic.id, &address, .main, block) == noErr {
                micListeners[mic.id] = block
            }
        }
        microphones = found
        micRunningChanged()
    }

    private func micRunningChanged() {
        for index in microphones.indices {
            microphones[index].running = Audio.isRunningSomewhere(microphones[index].id)
        }
        updateMicApps()
        let live = microphones.contains(where: \.running)
        if live, attributionTimer == nil {
            attributionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMicApps() }
            }
        } else if !live {
            attributionTimer?.invalidate()
            attributionTimer = nil
        }
    }

    /// Which apps are doing input on a live, real microphone. CoreAudio adds
    /// the process to its list a moment after the device starts, so this runs
    /// again on the attribution timer.
    private func updateMicApps() {
        guard #available(macOS 14.2, *) else {
            micApps = []
            return
        }
        canAttribute = true
        let live = Set(microphones.filter(\.running).map(\.id))
        guard !live.isEmpty else {
            if !micApps.isEmpty { micApps = [] }
            return
        }
        var apps: [App] = []
        for process in Audio.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            let devices = Audio.objects(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
            let usesLiveMic = devices.contains(where: live.contains)
                || (devices.isEmpty && Audio.value(process, kAudioProcessPropertyIsRunningInput, default: UInt32(0)) != 0)
            guard usesLiveMic else { continue }
            let pid: pid_t = Audio.value(process, kAudioProcessPropertyPID, default: -1)
            guard pid > 0, pid != getpid() else { continue }
            let app = Processes.app(pid: pid, bundleID: Audio.string(process, kAudioProcessPropertyBundleID))
            if !apps.contains(app) { apps.append(app) }
        }
        if apps != micApps { micApps = apps }
    }

    // MARK: Cameras

    private func reloadCameras() {
        let found = Video.devices().filter { !Video.isVirtual($0) }
        var address = Video.address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for (id, block) in cameraListeners where !found.contains(id) {
            CMIOObjectRemovePropertyListenerBlock(id, &address, .main, block)
            cameraListeners[id] = nil
        }
        for id in found where cameraListeners[id] == nil {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.cameraRunningChanged() }
            }
            if CMIOObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
                cameraListeners[id] = block
            }
        }
        cameras = found
        cameraRunningChanged()
    }

    private func cameraRunningChanged() {
        let running = cameras.contains(where: Video.isRunningSomewhere)
        if running != cameraRunning { cameraRunning = running }
    }
}

// MARK: CoreAudio

/// Thin wrappers over AudioObjectGetPropertyData.
enum Audio {
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, default fallback: T) -> T {
        var address = address(selector, scope: scope)
        var result = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? result : fallback
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    /// Virtual and aggregate devices run whenever their app is open, so they
    /// say nothing about a call. Teams' loopback driver is matched by UID too,
    /// in case it reports a physical transport.
    static func isVirtual(_ device: AudioObjectID) -> Bool {
        let transport: UInt32 = value(device, kAudioDevicePropertyTransportType, default: 0)
        if transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate { return true }
        return string(device, kAudioDevicePropertyDeviceUID)?.hasPrefix("MSLoopbackDriverDevice") ?? false
    }

    static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        value(device, kAudioDevicePropertyDeviceIsRunningSomewhere, default: UInt32(0)) != 0
    }

    static func transportName(_ device: AudioObjectID) -> String {
        let transport: UInt32 = value(device, kAudioDevicePropertyTransportType, default: 0)
        return fourCC(transport)
    }

    static func fourCC(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? String(code)
    }
}

// MARK: CoreMediaIO

/// The same "running somewhere" question for cameras.
enum Video {
    /// The virtual transport type, 'virt'.
    private static let virtual: UInt32 = 0x7669_7274

    static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func devices() -> [CMIOObjectID] {
        var address = address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func value(_ device: CMIOObjectID, _ selector: Int) -> UInt32? {
        var address = address(CMIOObjectPropertySelector(selector))
        var result: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &result)
        return status == noErr ? result : nil
    }

    static func isVirtual(_ device: CMIOObjectID) -> Bool {
        value(device, kCMIODevicePropertyTransportType) == virtual
    }

    static func isRunningSomewhere(_ device: CMIOObjectID) -> Bool {
        (value(device, kCMIODevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
    }
}

// MARK: Processes

enum Processes {
    static func path(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The app a process belongs to. Helpers live inside their app's bundle
    /// (Chrome's audio service is under Google Chrome.app), so the outermost
    /// `.app` in the path names it. A few system daemons do the audio for an
    /// app that isn't their parent, so those are named by hand.
    static func app(pid: pid_t, bundleID: String?) -> MeetingDetector.App {
        guard let path = path(pid) else {
            let running = NSRunningApplication(processIdentifier: pid)
            let isApp = running.map { $0.activationPolicy != .prohibited } ?? false
            return .init(name: running?.localizedName ?? bundleID ?? "An app", bundleID: running?.bundleIdentifier ?? bundleID, isSystem: !isApp)
        }
        if let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app") : nil) {
            let appPath = String(path[..<range.upperBound]).replacingOccurrences(of: ".app/", with: ".app")
            let bundle = Bundle(url: URL(fileURLWithPath: appPath))
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            return .init(name: name, bundleID: bundle?.bundleIdentifier ?? bundleID, isSystem: false)
        }
        let process = URL(fileURLWithPath: path).lastPathComponent
        switch process {
        // The two daemons that carry real calls for an app outside their own path.
        case "avconferenced": return .init(name: "FaceTime", bundleID: "com.apple.FaceTime", isSystem: false)
        case "com.apple.WebKit.GPU": return .init(name: "Safari", bundleID: "com.apple.Safari", isSystem: false)
        case "corespeechd": return .init(name: "Siri", bundleID: bundleID, isSystem: true)
        default: return .init(name: process, bundleID: bundleID, isSystem: true)
        }
    }
}
