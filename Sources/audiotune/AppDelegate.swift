import AppKit
import CoreAudio

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let monitor = AudioProcessMonitor()
    private let store = SettingsStore()

    private var taps: [String: ProcessTap] = [:]   // active taps keyed by stable app key

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        menu.delegate = self
        statusItem.menu = menu

        monitor.onChange = { [weak self] in self?.onRosterChange() }
        monitor.start()
        onRosterChange() // apply saved levels to whatever is already playing

        registerDefaultDeviceListener()
    }

    /// Rebuild active taps when the default output device changes (e.g. plugging
    /// in headphones) so tapped audio follows the new device instead of dying.
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

    private func onRosterChange() {
        pruneDeadTaps()
        autoAttachSavedApps()
        updateStatusIcon()
    }

    // MARK: - State (persisted, keyed by stable app key)

    private func setGain(_ key: String, _ name: String, _ value: Float) {
        store.update(key) {
            $0.gain = value
            if value > 0 { $0.muted = false }
        }
        applyToTap(key, name)
    }

    private func toggleMute(_ key: String, _ name: String) {
        store.update(key) {
            if $0.muted {
                $0.muted = false
                if $0.gain == 0 { $0.gain = 1.0 } // avoid unmuting into silence
            } else {
                $0.muted = true
            }
        }
        applyToTap(key, name)
    }

    private func togglePin(_ key: String) {
        store.update(key) { $0.pinned.toggle() }
        // Structural move between sections happens on next menu open; the row
        // already flipped its own pin glyph for immediate feedback.
    }

    /// Push the current effective gain to a live tap, creating one if needed.
    /// If the tap is still starting, updating its gain is safe (the render
    /// context is shared), so slider drags apply immediately either way.
    private func applyToTap(_ key: String, _ name: String) {
        if let tap = taps[key] {
            tap.setGain(store.settings(for: key).effectiveGain)
            updateStatusIcon()
        } else {
            startTapAsync(key, name)
        }
    }

    /// Create and start a tap off the main thread — AudioDeviceStart can block
    /// for seconds, which would otherwise freeze the menu. The tap is reserved
    /// in `taps` immediately so we never start two for one app and so gain
    /// changes during startup land on the shared render context.
    private func startTapAsync(_ key: String, _ name: String) {
        guard taps[key] == nil else { return }
        let ids = processObjectIDs(forKey: key)
        guard !ids.isEmpty else {
            Log.msg("startTap: no process objects for \(name) [\(key)]")
            return
        }
        let tap = ProcessTap(appName: name, processObjects: ids, gain: store.settings(for: key).effectiveGain)
        taps[key] = tap
        Task.detached { [tap] in
            let ok = tap.start()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if ok {
                    tap.setGain(self.store.settings(for: key).effectiveGain)
                } else if self.taps[key] === tap {
                    self.taps[key] = nil
                }
                self.updateStatusIcon()
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

    /// When an app with saved non-default levels is playing, attach and apply
    /// them automatically — so a level you set once "sticks" without reopening.
    private func autoAttachSavedApps() {
        let playing = dedupedByKey(monitor.processes.filter { $0.isRunningOutput })
        for proc in playing {
            let s = store.settings(for: proc.key)
            guard taps[proc.key] == nil, s.effectiveGain != 1.0 else { continue }
            Log.msg("auto-attach: \(proc.name) [\(proc.key)] -> gain \(s.effectiveGain)")
            applyToTap(proc.key, proc.name)
        }
    }

    // MARK: - Menu (rebuilt fresh each time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        monitor.refresh()
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "AudioTune", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let allApps = dedupedByKey(monitor.processes.filter { $0.isRegularApp || $0.isRunningOutput })
        let playingKeys = Set(monitor.processes.filter { $0.isRunningOutput }.map(\.key))

        func isMain(_ p: AudioProcess) -> Bool {
            playingKeys.contains(p.key) || store.settings(for: p.key).pinned
        }
        let main = allApps.filter(isMain).sorted { lhs, rhs in
            let lp = playingKeys.contains(lhs.key), rp = playingKeys.contains(rhs.key)
            if lp != rp { return lp }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let other = allApps.filter { !isMain($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if main.isEmpty {
            let placeholder = NSMenuItem(title: "No apps playing or pinned", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        } else {
            for proc in main { menu.addItem(sliderRow(for: proc)) }
        }

        if !other.isEmpty {
            menu.addItem(.separator())
            let sub = NSMenu()
            for proc in other { sub.addItem(sliderRow(for: proc)) }
            let item = NSMenuItem(title: "All apps — pin to add above (\(other.count))",
                                  action: nil, keyEquivalent: "")
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AudioTune", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
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

    private func sliderRow(for proc: AudioProcess) -> NSMenuItem {
        let item = NSMenuItem()
        let row = AppVolumeRowView()
        let key = proc.key
        let name = proc.name
        let appIcon = icon(for: proc)

        func reload() {
            let s = store.settings(for: key)
            row.configure(appName: name, icon: appIcon, gain: s.gain, muted: s.muted, pinned: s.pinned)
        }
        reload()

        row.onGainChange = { [weak self] v in self?.setGain(key, name, v) }
        row.onToggleMute = { [weak self] in
            self?.toggleMute(key, name)
            reload()
        }
        row.onTogglePin = { [weak self] in self?.togglePin(key) }

        item.view = row
        return item
    }

    // MARK: - Status-bar icon reflects whether anything is attenuated

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let anyActive = taps.values.contains { $0.gain != 1.0 }
        button.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "AudioTune")
        button.image?.isTemplate = true
        button.contentTintColor = anyActive ? .controlAccentColor : nil
    }

    @objc private func quitApp() {
        for tap in taps.values { tap.stop() }
        taps.removeAll()
        monitor.stop()
        NSApplication.shared.terminate(nil)
    }
}
