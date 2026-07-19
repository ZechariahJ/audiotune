import AppKit
import CoreAudio

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let monitor = AudioProcessMonitor()

    private var taps: [String: ProcessTap] = [:]     // active taps keyed by app name
    private var gains: [String: Float] = [:]         // last non-muted gain per app
    private var mutedApps: Set<String> = []          // apps currently muted

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "AudioTune")
            button.image?.isTemplate = true
        }

        menu.delegate = self
        statusItem.menu = menu

        // Keep the roster warm and prune taps for apps that quit.
        monitor.onChange = { [weak self] in self?.pruneDeadTaps() }
        monitor.start()

        maybeRunLaunchTest()
    }

    // MARK: - Gain / mute state

    private func effectiveGain(_ name: String) -> Float {
        mutedApps.contains(name) ? 0 : (gains[name] ?? 1.0)
    }

    private func setGain(_ name: String, _ value: Float) {
        gains[name] = value
        if value > 0 { mutedApps.remove(name) }
        if let tap = ensureTap(name) { tap.setGain(effectiveGain(name)) }
    }

    private func toggleMute(_ name: String) {
        if mutedApps.contains(name) {
            mutedApps.remove(name)
            if (gains[name] ?? 1.0) == 0 { gains[name] = 1.0 } // avoid unmuting to silence
        } else {
            mutedApps.insert(name)
        }
        if let tap = ensureTap(name) { tap.setGain(effectiveGain(name)) }
    }

    /// Lazily create (and start) a tap for an app the first time it's controlled.
    private func ensureTap(_ name: String) -> ProcessTap? {
        if let existing = taps[name] { return existing }
        let ids = processObjectIDs(forAppNamed: name)
        guard !ids.isEmpty else {
            Log.msg("ensureTap: no process objects for \(name)")
            return nil
        }
        let tap = ProcessTap(appName: name, processObjects: ids, gain: effectiveGain(name))
        guard tap.start() else { return nil }
        taps[name] = tap
        return tap
    }

    private func processObjectIDs(forAppNamed name: String) -> [AudioObjectID] {
        let matches = monitor.processes.filter { $0.name == name }
        let producing = matches.filter { $0.isRunningOutput }
        return (producing.isEmpty ? matches : producing).map(\.id)
    }

    private func pruneDeadTaps() {
        let liveNames = Set(monitor.processes.map(\.name))
        for name in taps.keys where !liveNames.contains(name) {
            taps[name]?.stop()
            taps[name] = nil
            Log.msg("pruned tap for departed app: \(name)")
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

        let active = dedupedByName(monitor.processes.filter { $0.isRunningOutput })
        let activeNames = Set(active.map(\.name))
        let idle = dedupedByName(
            monitor.processes.filter { !$0.isRunningOutput && $0.isRegularApp && !activeNames.contains($0.name) }
        )

        if active.isEmpty {
            let placeholder = NSMenuItem(title: "No apps playing audio", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        } else {
            for proc in active { menu.addItem(sliderRow(for: proc)) }
        }

        if !idle.isEmpty {
            menu.addItem(.separator())
            let sub = NSMenu()
            for proc in idle { sub.addItem(sliderRow(for: proc)) }
            let item = NSMenuItem(title: "Other apps (\(idle.count))", action: nil, keyEquivalent: "")
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AudioTune", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func dedupedByName(_ procs: [AudioProcess]) -> [AudioProcess] {
        var seen = Set<String>()
        return procs.filter { seen.insert($0.name).inserted }
    }

    private func sliderRow(for proc: AudioProcess) -> NSMenuItem {
        let item = NSMenuItem()
        let row = AppVolumeRowView()
        let name = proc.name
        let icon = NSRunningApplication(processIdentifier: proc.pid)?.icon

        row.configure(
            appName: name,
            icon: icon,
            gain: gains[name] ?? 1.0,
            muted: mutedApps.contains(name)
        )
        row.onGainChange = { [weak self] v in self?.setGain(name, v) }
        row.onToggleMute = { [weak self, weak row] in
            guard let self else { return }
            self.toggleMute(name)
            row?.configure(
                appName: name,
                icon: icon,
                gain: self.gains[name] ?? 1.0,
                muted: self.mutedApps.contains(name)
            )
        }

        item.view = row
        return item
    }

    // MARK: - Launch test hook (kept for headless verification)

    private func maybeRunLaunchTest() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/audiotune")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              let marker = files.first(where: { $0.hasPrefix(".test-") }) else { return }
        let appName = String(marker.dropFirst(".test-".count))
        Log.msg("launch-test: gain sweep on '\(appName)' in 1.5s (keep it playing)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.monitor.refresh()
            self.setGain(appName, 1.0)          // creates the tap
            self.sweep(appName, gains: [1.0, 0.5, 0.1, 1.0], step: 0)
        }
    }

    /// Measure output peak at each gain to confirm scaling. Peaks should track
    /// the gain ratio (given a steady source), proving the slider attenuates.
    private func sweep(_ name: String, gains: [Float], step: Int) {
        guard step < gains.count, let tap = taps[name] else { return }
        let g = gains[step]
        setGain(name, g)
        tap.resetPeak()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, let tap = self.taps[name] else { return }
            Log.msg(String(format: "launch-test: gain %.2f -> output peak %.4f", g, tap.currentPeak))
            self.sweep(name, gains: gains, step: step + 1)
        }
    }

    @objc private func quitApp() {
        for tap in taps.values { tap.stop() }
        taps.removeAll()
        monitor.stop()
        NSApplication.shared.terminate(nil)
    }
}
