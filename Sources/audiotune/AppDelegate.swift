import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "slider.vertical.3",
                accessibilityDescription: "AudioTune"
            )
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "AudioTune", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let placeholder = NSMenuItem(
            title: "No apps playing audio yet",
            action: nil,
            keyEquivalent: ""
        )
        placeholder.isEnabled = false
        menu.addItem(placeholder)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(title: "Quit AudioTune", action: #selector(quit), keyEquivalent: "q")
        )
        menu.items.last?.target = self

        return menu
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
