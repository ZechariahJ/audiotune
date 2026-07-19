import AppKit
import CoreAudio

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = AudioProcessMonitor()
    private var taps: [String: ProcessTap] = [:]   // keyed by app name

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "slider.vertical.3",
                accessibilityDescription: "AudioTune"
            )
            button.image?.isTemplate = true
        }

        monitor.onChange = { [weak self] in self?.rebuildMenu() }
        monitor.start()
        rebuildMenu()

        maybeRunLaunchTest()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

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
            let label = NSMenuItem(title: "Playing now — click to toggle passthrough", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            for proc in active {
                menu.addItem(processItem(proc, active: true))
            }
        }

        if !idle.isEmpty {
            menu.addItem(.separator())
            let other = NSMenu()
            for proc in idle {
                other.addItem(processItem(proc, active: false))
            }
            let otherItem = NSMenuItem(title: "Other audio apps (\(idle.count))", action: nil, keyEquivalent: "")
            otherItem.submenu = other
            menu.addItem(otherItem)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AudioTune", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// Keep the first process object per display name (helpers roll up to one app).
    private func dedupedByName(_ procs: [AudioProcess]) -> [AudioProcess] {
        var seen = Set<String>()
        return procs.filter { seen.insert($0.name).inserted }
    }

    private func processItem(_ proc: AudioProcess, active: Bool) -> NSMenuItem {
        let tapped = taps[proc.name] != nil
        let item = NSMenuItem(title: proc.name, action: #selector(toggleTap(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = proc.name

        if let app = NSRunningApplication(processIdentifier: proc.pid), let icon = app.icon {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        item.state = tapped ? .on : .off // checkmark when we're actively passing it through
        if active && !tapped {
            item.onStateImage = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
        }
        return item
    }

    // MARK: - Actions

    @objc private func toggleTap(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        if let existing = taps[name] {
            existing.stop()
            taps[name] = nil
        } else {
            startTap(forAppNamed: name)
        }
        rebuildMenu()
    }

    /// Collect every audio process object belonging to an app (helpers included)
    /// so the tap covers whichever process is actually producing sound.
    private func processObjectIDs(forAppNamed name: String) -> [AudioObjectID] {
        let matches = monitor.processes.filter { $0.name == name }
        let producing = matches.filter { $0.isRunningOutput }
        return (producing.isEmpty ? matches : producing).map(\.id)
    }

    @discardableResult
    private func startTap(forAppNamed name: String) -> Bool {
        let ids = processObjectIDs(forAppNamed: name)
        guard !ids.isEmpty else {
            Log.msg("startTap: no process objects for \(name)")
            return false
        }
        let tap = ProcessTap(appName: name, processObjects: ids, gain: 1.0)
        guard tap.start() else { return false }
        taps[name] = tap
        return true
    }

    // MARK: - Launch test hook (M2 verification)

    /// If ~/Documents/audiotune/.test-<app> exists, auto-start passthrough on
    /// that app shortly after launch so we can verify the pipeline headlessly.
    private func maybeRunLaunchTest() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/audiotune")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        guard let marker = files.first(where: { $0.hasPrefix(".test-") }) else { return }
        let appName = String(marker.dropFirst(".test-".count))
        Log.msg("launch-test: will attempt passthrough for '\(appName)' in 1.5s")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.monitor.refresh()
            let ok = self?.startTap(forAppNamed: appName) ?? false
            Log.msg("launch-test: startTap(\(appName)) ->", ok)
            self?.rebuildMenu()
        }
    }

    @objc private func quitApp() {
        for tap in taps.values { tap.stop() }
        taps.removeAll()
        monitor.stop()
        NSApplication.shared.terminate(nil)
    }
}
