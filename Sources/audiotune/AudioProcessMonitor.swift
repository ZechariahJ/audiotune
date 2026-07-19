import AppKit
import CoreAudio

/// A process known to Core Audio that is (or can be) doing audio I/O.
struct AudioProcess: Identifiable, Equatable {
    let id: AudioObjectID          // Core Audio process-object id
    let pid: pid_t
    let bundleID: String?
    let key: String                // stable per-app identity (parent bundle id for helpers)
    let name: String               // best display name we can resolve (parent app for helpers)
    let bundleURL: URL?            // app bundle, for reliable icon lookup
    let isRunningOutput: Bool      // currently producing output audio
    let isRegularApp: Bool         // a user-facing app (not a daemon/agent)

    static func == (lhs: AudioProcess, rhs: AudioProcess) -> Bool {
        lhs.id == rhs.id && lhs.isRunningOutput == rhs.isRunningOutput
    }
}

/// Enumerates Core Audio process objects and notifies when the set changes.
@MainActor
final class AudioProcessMonitor {
    private(set) var processes: [AudioProcess] = []
    var onChange: (() -> Void)?

    private var pollTimer: Timer?

    func start() {
        refresh()
        // Poll for changes to the running-output state (per-process listeners
        // would be tighter; a light poll is plenty for a menu we only open now
        // and then, and it also catches add/remove of process objects).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        let latest = Self.enumerateProcesses()
        if latest != processes {
            processes = latest
            onChange?()
        }
    }

    // MARK: - Core Audio enumeration

    private static func enumerateProcesses() -> [AudioProcess] {
        let objectIDs = systemProcessObjectIDs()
        var result: [AudioProcess] = []
        result.reserveCapacity(objectIDs.count)

        for objID in objectIDs {
            guard let pid: pid_t = getProperty(objID, kAudioProcessPropertyPID) else { continue }
            let bundleID: String? = getCFStringProperty(objID, kAudioProcessPropertyBundleID)
            let runningOut: UInt32 = getProperty(objID, kAudioProcessPropertyIsRunningOutput) ?? 0

            let info = resolveApp(pid: pid, bundleID: bundleID)
            result.append(
                AudioProcess(
                    id: objID,
                    pid: pid,
                    bundleID: bundleID,
                    key: info.key,
                    name: info.name,
                    bundleURL: info.bundleURL,
                    isRunningOutput: runningOut != 0,
                    isRegularApp: info.isRegular
                )
            )
        }

        // Apps actively producing output first, then alphabetical.
        return result.sorted {
            if $0.isRunningOutput != $1.isRunningOutput { return $0.isRunningOutput }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func systemProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBytes { buf in
            AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, buf.baseAddress!)
        }
        return status == noErr ? ids : []
    }

    // MARK: - Property helpers

    /// Read a fixed-layout property (pid_t, UInt32, …) from an audio object.
    private static func getProperty<T>(_ objID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var dataSize = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(objID, &address, 0, nil, &dataSize, value)
        guard status == noErr else { return nil }
        return value.pointee
    }

    private static func getCFStringProperty(_ objID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var cfString: CFString? = nil
        let status = withUnsafeMutablePointer(to: &cfString) { ptr in
            AudioObjectGetPropertyData(objID, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr, let s = cfString else { return nil }
        return s as String
    }

    private struct AppInfo {
        var key: String
        var name: String
        var bundleURL: URL?
        var isRegular: Bool
    }

    /// Resolve a stable identity, friendly name, bundle URL (for icons), and
    /// whether this is a real user-facing app. Helper processes (e.g. "Discord
    /// Helper (Renderer)", bundle `com.hnc.Discord.helper.Renderer`) are rolled
    /// up to their parent app so one app shows once and shares one identity.
    private static func resolveApp(pid: pid_t, bundleID: String?) -> AppInfo {
        // Roll a helper up to its parent app via bundle-ID prefix.
        if let bundleID, let range = bundleID.range(of: ".helper") {
            let parentID = String(bundleID[bundleID.startIndex..<range.lowerBound])
            if let parent = NSRunningApplication.runningApplications(withBundleIdentifier: parentID).first {
                return AppInfo(
                    key: parentID,
                    name: parent.localizedName ?? parentID,
                    bundleURL: parent.bundleURL ?? appURL(forBundleID: parentID),
                    isRegular: parent.activationPolicy == .regular
                )
            }
            // Parent isn't a separate running process (self-contained app): still
            // use the parent bundle id as the identity and look up its icon.
            if let url = appURL(forBundleID: parentID) {
                return AppInfo(key: parentID, name: url.deletingPathExtension().lastPathComponent,
                               bundleURL: url, isRegular: true)
            }
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            let key = app.bundleIdentifier ?? bundleID ?? "pid:\(pid)"
            return AppInfo(
                key: key,
                name: app.localizedName ?? bundleID ?? "PID \(pid)",
                bundleURL: app.bundleURL ?? bundleID.flatMap(appURL(forBundleID:)),
                isRegular: app.activationPolicy == .regular
            )
        }

        if let bundleID, !bundleID.isEmpty {
            return AppInfo(
                key: bundleID,
                name: bundleID.components(separatedBy: ".").last ?? bundleID,
                bundleURL: appURL(forBundleID: bundleID),
                isRegular: false
            )
        }
        return AppInfo(key: "pid:\(pid)", name: "PID \(pid)", bundleURL: nil, isRegular: false)
    }

    private static func appURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
