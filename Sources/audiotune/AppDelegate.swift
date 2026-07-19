import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private let mixer = AudioMixer()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusMenu.delegate = self
        statusItem.menu = statusMenu

        mixer.start()
        updateStatusIcon()
        // Note: the window is intentionally NOT shown at launch.
    }

    // MARK: - Window (created lazily; opened from Dock / menu)

    @objc func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: MixerView(mixer: mixer))
            hosting.sizingOptions = [] // don't let SwiftUI's ideal size drive the window

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "AudioTune"
            w.contentViewController = hosting
            // Must set the size AFTER the content controller, which otherwise
            // collapses the window to its (zero) preferred content size.
            w.setContentSize(NSSize(width: 420, height: 560))
            w.contentMinSize = NSSize(width: 380, height: 460)
            w.contentMaxSize = NSSize(width: 640, height: 5000)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Clicking the Dock icon (when no window is open) opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    /// Right-click / long-press on the Dock icon.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open AudioTune", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset all volumes", action: #selector(resetTapped), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        return menu
    }

    // MARK: - Menu-bar menu (rebuilt fresh on open, sourced from the mixer)

    func menuNeedsUpdate(_ menu: NSMenu) {
        mixer.refreshRoster()
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: "Open Window", action: #selector(showWindow), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        menu.addItem(masterRow())
        menu.addItem(.separator())

        let main = mixer.apps.filter { $0.isPlaying || $0.settings.pinned }
        let other = mixer.apps.filter { !($0.isPlaying || $0.settings.pinned) }

        if main.isEmpty {
            let placeholder = NSMenuItem(title: "No apps playing or pinned", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        } else {
            for app in main { menu.addItem(sliderRow(for: app)) }
        }

        if !other.isEmpty {
            menu.addItem(.separator())
            let sub = NSMenu()
            for app in other { sub.addItem(sliderRow(for: app)) }
            let item = NSMenuItem(title: "All apps — pin to add above (\(other.count))",
                                  action: nil, keyEquivalent: "")
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset all volumes", action: #selector(resetTapped), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AudioTune", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func masterRow() -> NSMenuItem {
        let item = NSMenuItem()
        let row = AppVolumeRowView()
        let masterIcon = NSImage(systemSymbolName: "hifispeaker.2.fill", accessibilityDescription: nil)

        func reload() {
            let m = mixer.master
            row.configure(appName: "All Apps", icon: masterIcon,
                          gain: m.gain, muted: m.muted, pinned: false, showsPin: false)
        }
        reload()
        row.onGainChange = { [weak self] v in self?.mixer.setMasterGain(v) }
        row.onToggleMute = { [weak self] in
            self?.mixer.toggleMasterMute()
            reload()
        }
        item.view = row
        return item
    }

    private func sliderRow(for app: AudioMixer.MixerApp) -> NSMenuItem {
        let item = NSMenuItem()
        let row = AppVolumeRowView()
        let key = app.key
        let name = app.name

        func reload() {
            let s = mixer.apps.first(where: { $0.key == key })?.settings ?? app.settings
            row.configure(appName: name, icon: app.icon, gain: s.gain, muted: s.muted, pinned: s.pinned)
        }
        reload()

        row.onGainChange = { [weak self] v in self?.mixer.setGain(key, name, v) }
        row.onToggleMute = { [weak self] in
            self?.mixer.toggleMute(key, name)
            reload()
        }
        row.onTogglePin = { [weak self] in self?.mixer.togglePin(key) }
        item.view = row
        return item
    }

    // MARK: - Status-bar icon

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "AudioTune")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = mixer.isAnythingAttenuated ? .controlAccentColor : nil
    }

    // MARK: - Actions

    @objc private func resetTapped() { mixer.resetAll(); updateStatusIcon() }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let nowEnabled = LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = nowEnabled ? .on : .off
    }

    @objc private func quitApp() {
        mixer.stopAll()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Main menu (standard app menu for a regular app)

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About AudioTune",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "Hide AudioTune", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = .command
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit AudioTune", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        appItem.submenu = appMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        let openWin = windowMenu.addItem(withTitle: "AudioTune", action: #selector(showWindow), keyEquivalent: "0")
        openWin.target = self
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}
