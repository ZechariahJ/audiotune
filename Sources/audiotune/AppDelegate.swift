import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = AudioProcessMonitor()

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
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "AudioTune", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Collapse rolled-up helpers so one app shows once. "Playing now" shows
        // anything producing output; the idle list is limited to real apps.
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
            let label = NSMenuItem(title: "Playing now", action: nil, keyEquivalent: "")
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
        let item = NSMenuItem(title: proc.name, action: nil, keyEquivalent: "")
        item.isEnabled = false // sliders come in M3; for now just show the roster

        if let app = NSRunningApplication(processIdentifier: proc.pid), let icon = app.icon {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        if active {
            item.onStateImage = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
            item.state = .on
        }
        return item
    }

    @objc private func quitApp() {
        monitor.stop()
        NSApplication.shared.terminate(nil)
    }
}
