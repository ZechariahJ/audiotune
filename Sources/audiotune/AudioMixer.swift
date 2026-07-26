import AppKit
import CoreAudio
import Combine

/// The single source of truth for the app's audio state. Both the menu-bar UI
/// and the window observe and drive this, so they stay perfectly in sync.
@MainActor
final class AudioMixer: ObservableObject {
    /// A view-model row for one controllable app.
    struct MixerApp: Identifiable, Equatable {
        let key: String
        let name: String
        let icon: NSImage?
        let isPlaying: Bool
        var settings: AppAudioSettings
        var id: String { key }

        static func == (l: MixerApp, r: MixerApp) -> Bool {
            l.key == r.key && l.name == r.name && l.isPlaying == r.isPlaying && l.settings == r.settings
        }
    }

    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var master = AppAudioSettings()
    @Published private(set) var appearance: AppearanceMode = .system
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfileID: String?
    @Published private(set) var hotkeys: [HotkeyBinding] = []

    /// Fired when hotkey bindings change so the app can re-register them.
    var onHotkeysChanged: (() -> Void)?

    private let monitor = AudioProcessMonitor()
    private let store = SettingsStore()
    private var taps: [String: ProcessTap] = [:]

    // MARK: - Lifecycle

    func start() {
        master = store.master
        appearance = store.appearance
        profiles = store.profiles
        activeProfileID = store.activeProfileID
        hotkeys = store.hotkeyBindings
        applyAppearance()
        monitor.onChange = { [weak self] in self?.onRosterChange() }
        monitor.start()
        onRosterChange()
        registerDefaultDeviceListener()
    }

    // MARK: - Appearance

    func setAppearance(_ mode: AppearanceMode) {
        store.appearance = mode
        appearance = mode
        applyAppearance()
    }

    /// nil appearance = follow the system (updates live when the OS switches).
    private func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func stopAll() {
        for tap in taps.values { tap.stop() }
        taps.removeAll()
        monitor.stop()
    }

    /// Force a fresh enumeration (call before showing the menu).
    func refreshRoster() {
        monitor.refresh()
        rebuildApps()
    }

    private func onRosterChange() {
        pruneDeadTaps()
        autoAttachSavedApps()
        rebuildApps()
    }

    // MARK: - Derived roster

    private func rebuildApps() {
        let deduped = dedupedByKey(monitor.processes.filter { $0.isRegularApp || $0.isRunningOutput })
        let playingKeys = Set(monitor.processes.filter { $0.isRunningOutput }.map(\.key))

        apps = deduped.map { p in
            MixerApp(key: p.key, name: p.name, icon: icon(for: p),
                     isPlaying: playingKeys.contains(p.key), settings: store.settings(for: p.key))
        }
        .sorted { a, b in
            if a.isPlaying != b.isPlaying { return a.isPlaying }
            if a.settings.pinned != b.settings.pinned { return a.settings.pinned }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func patchApp(_ key: String) {
        guard let i = apps.firstIndex(where: { $0.key == key }) else { return }
        apps[i].settings = store.settings(for: key)
    }

    // MARK: - Per-app controls

    func setGain(_ key: String, _ name: String, _ value: Float) {
        store.update(key) {
            $0.gain = value
            if value > 0 { $0.muted = false }
        }
        applyToTap(key, name)
        patchApp(key)
    }

    func toggleMute(_ key: String, _ name: String) {
        store.update(key) {
            if $0.muted {
                $0.muted = false
                if $0.gain == 0 { $0.gain = 1.0 }
            } else {
                $0.muted = true
            }
        }
        applyToTap(key, name)
        patchApp(key)
    }

    func togglePin(_ key: String) {
        store.update(key) { $0.pinned.toggle() }
        rebuildApps() // pinning moves the app between sections
    }

    // MARK: - Profiles

    var activeProfileName: String? {
        activeProfileID.flatMap { id in profiles.first { $0.id == id }?.name }
    }

    /// Create a profile from the current levels.
    @discardableResult
    func createProfile(named name: String) -> Profile {
        let snap = store.currentAsSnapshot()
        let profile = Profile(name: name, apps: snap.apps, master: snap.master)
        store.addProfile(profile)
        profiles = store.profiles
        return profile
    }

    func renameProfile(id: String, to name: String) {
        guard var p = store.profile(id: id) else { return }
        p.name = name
        store.updateProfile(p)
        profiles = store.profiles
    }

    /// Overwrite a profile's stored levels with what's currently set.
    func updateProfileFromCurrent(id: String) {
        guard var p = store.profile(id: id) else { return }
        let snap = store.currentAsSnapshot()
        p.apps = snap.apps
        p.master = snap.master
        store.updateProfile(p)
        profiles = store.profiles
    }

    func deleteProfile(id: String) {
        store.deleteProfile(id: id)
        profiles = store.profiles
        activeProfileID = store.activeProfileID
        hotkeys = store.hotkeyBindings
        onHotkeysChanged?()
    }

    /// Apply a profile's levels to every app and the master, live.
    func activateProfile(id: String) {
        guard let p = store.profile(id: id) else { return }
        store.applyProfile(p)
        activeProfileID = id
        master = store.master
        Log.msg("activated profile '\(p.name)'")
        reapplyAllGains()
        rebuildApps()
    }

    /// Leave profile mode: levels stay as they are, nothing is "active".
    func activateDefault() {
        store.setActiveProfile(nil)
        activeProfileID = nil
    }

    /// Push current effective gains to every live tap and attach any playing app
    /// that now needs attenuating.
    private func reapplyAllGains() {
        for (key, tap) in taps { tap.setGain(effectiveTapGain(key)) }
        for proc in dedupedByKey(monitor.processes.filter { $0.isRunningOutput }) where taps[proc.key] == nil {
            if effectiveTapGain(proc.key) != 1.0 { applyToTap(proc.key, proc.name) }
        }
    }

    // MARK: - Hotkeys

    func combo(for action: HotkeyAction) -> HotkeyCombo? {
        hotkeys.first { $0.action == action }?.combo
    }

    func setCombo(_ combo: HotkeyCombo?, for action: HotkeyAction) {
        store.setCombo(combo, for: action)
        hotkeys = store.hotkeyBindings
        onHotkeysChanged?()
    }

    func resetHotkeys() {
        store.resetHotkeysToDefaults()
        hotkeys = store.hotkeyBindings
        onHotkeysChanged?()
    }

    /// Execute a bound action. Returns HUD content when there's something to show.
    func perform(_ action: HotkeyAction) -> HUDInfo? {
        let step: Float = 0.05
        switch action {
        case .frontmostVolumeUp:   return adjustFrontmostVolume(by: step)
        case .frontmostVolumeDown: return adjustFrontmostVolume(by: -step)
        case .frontmostMute:       return toggleFrontmostMute()

        case .masterVolumeUp:      return nudgeMaster(by: step)
        case .masterVolumeDown:    return nudgeMaster(by: -step)
        case .masterMute:
            toggleMasterMute()
            return masterHUD()

        case .appVolumeUp(let key):   return nudgeApp(key, by: step)
        case .appVolumeDown(let key): return nudgeApp(key, by: -step)
        case .appMute(let key):
            guard let app = apps.first(where: { $0.key == key }) else { return nil }
            toggleMute(key, app.name)
            let s = store.settings(for: key)
            return HUDInfo(name: app.name, icon: app.icon, volume: s.effectiveGain, muted: s.muted)

        case .activateProfile(let id):
            guard let p = store.profile(id: id) else { return nil }
            activateProfile(id: id)
            return HUDInfo(name: p.name, icon: Self.symbolIcon("square.stack.3d.up.fill"),
                           volume: store.master.effectiveGain, muted: store.master.muted)
        case .activateDefault:
            activateDefault()
            return HUDInfo(name: "Default", icon: Self.symbolIcon("square.stack.3d.up.slash"),
                           volume: store.master.effectiveGain, muted: store.master.muted)
        }
    }

    private func nudgeMaster(by delta: Float) -> HUDInfo? {
        let next = max(0, min(1, ((store.master.gain + delta) * 100).rounded() / 100))
        setMasterGain(next)
        return masterHUD()
    }

    private func nudgeApp(_ key: String, by delta: Float) -> HUDInfo? {
        guard let app = apps.first(where: { $0.key == key }) else { return nil }
        let next = max(0, min(1, ((store.settings(for: key).gain + delta) * 100).rounded() / 100))
        setGain(key, app.name, next)
        let s = store.settings(for: key)
        return HUDInfo(name: app.name, icon: app.icon, volume: s.effectiveGain, muted: s.muted)
    }

    private func masterHUD() -> HUDInfo {
        HUDInfo(name: "All Apps", icon: Self.symbolIcon("hifispeaker.2.fill"),
                volume: store.master.effectiveGain, muted: store.master.muted)
    }

    private static func symbolIcon(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    // MARK: - Frontmost-app control (for global hotkeys)

    struct HUDInfo {
        let name: String
        let icon: NSImage?
        let volume: Float
        let muted: Bool
    }

    private func frontmostApp() -> (key: String, name: String, icon: NSImage?)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return nil }
        let icon = app.icon ?? app.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        return (bundleID, app.localizedName ?? bundleID, icon)
    }

    @discardableResult
    func adjustFrontmostVolume(by delta: Float) -> HUDInfo? {
        guard let f = frontmostApp() else { return nil }
        let current = store.settings(for: f.key).gain
        let newGain = max(0, min(1, ((current + delta) * 100).rounded() / 100))
        setGain(f.key, f.name, newGain)
        let s = store.settings(for: f.key)
        return HUDInfo(name: f.name, icon: f.icon, volume: s.effectiveGain, muted: s.muted)
    }

    @discardableResult
    func toggleFrontmostMute() -> HUDInfo? {
        guard let f = frontmostApp() else { return nil }
        toggleMute(f.key, f.name)
        let s = store.settings(for: f.key)
        return HUDInfo(name: f.name, icon: f.icon, volume: s.effectiveGain, muted: s.muted)
    }

    // MARK: - Master + reset

    func setMasterGain(_ value: Float) {
        store.updateMaster {
            $0.gain = value
            if value > 0 { $0.muted = false }
        }
        master = store.master
        applyMasterEverywhere()
    }

    func toggleMasterMute() {
        store.updateMaster {
            if $0.muted {
                $0.muted = false
                if $0.gain == 0 { $0.gain = 1.0 }
            } else {
                $0.muted = true
            }
        }
        master = store.master
        applyMasterEverywhere()
    }

    func resetAll() {
        store.resetVolumes()
        for tap in taps.values { tap.stop() }
        taps.removeAll()
        master = store.master
        rebuildApps()
    }

    private func applyMasterEverywhere() {
        for (key, tap) in taps { tap.setGain(effectiveTapGain(key)) }
        if store.master.effectiveGain != 1.0 {
            for proc in dedupedByKey(monitor.processes.filter { $0.isRunningOutput }) where taps[proc.key] == nil {
                applyToTap(proc.key, proc.name)
            }
        }
    }

    // MARK: - Tap plumbing

    private func effectiveTapGain(_ key: String) -> Float {
        store.master.effectiveGain * store.settings(for: key).effectiveGain
    }

    private func applyToTap(_ key: String, _ name: String) {
        if let tap = taps[key] {
            tap.setGain(effectiveTapGain(key))
        } else {
            startTapAsync(key, name)
        }
    }

    private func startTapAsync(_ key: String, _ name: String) {
        guard taps[key] == nil else { return }
        let ids = processObjectIDs(forKey: key)
        guard !ids.isEmpty else {
            Log.msg("startTap: no process objects for \(name) [\(key)]")
            return
        }
        let tap = ProcessTap(appName: name, processObjects: ids, gain: effectiveTapGain(key))
        taps[key] = tap
        Task.detached { [tap] in
            let ok = tap.start()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if ok {
                    tap.setGain(self.effectiveTapGain(key))
                } else if self.taps[key] === tap {
                    self.taps[key] = nil
                }
            }
        }
    }

    private func processObjectIDs(forKey key: String) -> [AudioObjectID] {
        let matches = monitor.processes.filter { $0.key == key }
        let producing = matches.filter { $0.isRunningOutput }
        return (producing.isEmpty ? matches : producing).map(\.id)
    }

    private func pruneDeadTaps() {
        let liveKeys = Set(monitor.processes.map(\.key))
        for key in taps.keys where !liveKeys.contains(key) {
            taps[key]?.stop()
            taps[key] = nil
            Log.msg("pruned tap for departed app: \(key)")
        }
    }

    private func autoAttachSavedApps() {
        let playing = dedupedByKey(monitor.processes.filter { $0.isRunningOutput })
        for proc in playing {
            guard taps[proc.key] == nil, effectiveTapGain(proc.key) != 1.0 else { continue }
            Log.msg("auto-attach: \(proc.name) [\(proc.key)] -> gain \(effectiveTapGain(proc.key))")
            applyToTap(proc.key, proc.name)
        }
    }

    // MARK: - Output device follow

    private func registerDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.taps.isEmpty else { return }
                Log.msg("default output changed — rebuilding \(self.taps.count) tap(s)")
                self.rebuildAllTaps()
            }
        }
    }

    private func rebuildAllTaps() {
        let entries = taps.map { (key: $0.key, name: $0.value.appName) }
        for entry in entries {
            taps[entry.key]?.stop()
            taps[entry.key] = nil
        }
        monitor.refresh()
        for entry in entries { startTapAsync(entry.key, entry.name) }
    }

    // MARK: - Helpers

    var isAnythingAttenuated: Bool {
        store.master.effectiveGain != 1.0 || apps.contains { !$0.settings.isDefault && $0.settings.effectiveGain != 1.0 }
    }

    private func dedupedByKey(_ procs: [AudioProcess]) -> [AudioProcess] {
        var seen = Set<String>()
        return procs.filter { seen.insert($0.key).inserted }
    }

    private func icon(for proc: AudioProcess) -> NSImage? {
        if let url = proc.bundleURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let app = NSRunningApplication(processIdentifier: proc.pid), let i = app.icon {
            return i
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
    }
}
