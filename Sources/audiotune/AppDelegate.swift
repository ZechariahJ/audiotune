import AppKit
import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private let mixer = AudioMixer()
    private let hotKeys = GlobalHotKeys()
    private let hud = VolumeHUD()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.mainMenu = buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusMenu.delegate = self
        statusItem.menu = statusMenu

        mixer.onHotkeysChanged = { [weak self] in self?.registerHotKeys() }
        mixer.start()
        updateStatusIcon()
        registerHotKeys()
        observeSystemAppearanceChanges()
        // Note: the window is intentionally NOT shown at launch.
    }

    // MARK: - Global hotkeys (built from the user's bindings)

    private func registerHotKeys() {
        var nextID: UInt32 = 1
        var list: [GlobalHotKeys.Binding] = []
        for binding in mixer.hotkeys {
            let action = binding.action
            list.append(.init(id: nextID,
                              keyCode: binding.combo.keyCode,
                              modifiers: binding.combo.modifiers,
                              repeats: action.repeats,
                              action: { [weak self] in self?.performAction(action) }))
            nextID += 1
        }
        let failed = hotKeys.register(list)
        if !failed.isEmpty {
            Log.msg("hotkeys: \(failed.count) binding(s) rejected — already claimed system-wide")
        }
    }

    private func performAction(_ action: HotkeyAction) {
        guard let info = mixer.perform(action) else { return }
        hud.show(name: info.name, icon: info.icon, volume: info.volume, muted: info.muted)
        updateStatusIcon()
    }

    // MARK: - Window (created lazily; opened from Dock / menu)

    @objc func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainWindowView(mixer: mixer))
            hosting.sizingOptions = [] // don't let SwiftUI's ideal size drive the window

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "AudioTune"
            w.contentViewController = hosting
            // Must set the size AFTER the content controller, which otherwise
            // collapses the window to its (zero) preferred content size.
            w.setContentSize(NSSize(width: 520, height: 620))
            w.contentMinSize = NSSize(width: 470, height: 480)
            w.contentMaxSize = NSSize(width: 900, height: 5000)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        // Become a regular app so the window gets a Dock icon, a main menu and a
        // Cmd-Tab entry while it's on screen.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closing the window drops the Dock icon again — the app keeps running in
    /// the menu bar.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        // Defer past the close so AppKit finishes tearing the window down first.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Clicking the Dock icon (when no window is open) opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    /// Right-click / long-press on the Dock icon: switch presets without
    /// opening the window.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open AudioTune", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        let header = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for item in presetMenuItems() { menu.addItem(item) }

        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset all volumes", action: #selector(resetTapped), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        return menu
    }

    /// "Default" plus every saved preset, with the active one checked.
    /// Shared by the Dock menu and the menu-bar menu.
    private func presetMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let def = NSMenuItem(title: "Default", action: #selector(selectDefaultPreset), keyEquivalent: "")
        def.target = self
        def.state = mixer.activeProfileID == nil ? .on : .off
        items.append(def)

        for profile in mixer.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = mixer.activeProfileID == profile.id ? .on : .off
            if let combo = mixer.combo(for: .activateProfile(profile.id)) {
                item.toolTip = "Shortcut: \(combo.display)"
            }
            items.append(item)
        }

        if mixer.profiles.isEmpty {
            let hint = NSMenuItem(title: "No presets — create one in the window", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            items.append(hint)
        }
        return items
    }

    @objc private func selectDefaultPreset() {
        mixer.activateDefault()
        updateStatusIcon()
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        mixer.activateProfile(id: id)
        updateStatusIcon()
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

        let presetsItem = NSMenuItem(
            title: "Preset: \(mixer.activeProfileName ?? "Default")", action: nil, keyEquivalent: ""
        )
        let presetsSub = NSMenu()
        for item in presetMenuItems() { presetsSub.addItem(item) }
        presetsItem.submenu = presetsSub
        menu.addItem(presetsItem)

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

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceSub = NSMenu()
        for mode in AppearanceMode.allCases {
            let mi = NSMenuItem(title: mode.label, action: #selector(setAppearanceMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            mi.state = (mixer.appearance == mode) ? .on : .off
            appearanceSub.addItem(mi)
        }
        appearanceItem.submenu = appearanceSub
        menu.addItem(appearanceItem)

        let shortcutsItem = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
        let shortcutsSub = NSMenu()
        for action in HotkeyAction.globalActions {
            let combo = mixer.combo(for: action)?.display ?? "Not set"
            let mi = NSMenuItem(title: "\(action.globalLabel ?? "")\t\(combo)", action: nil, keyEquivalent: "")
            mi.isEnabled = false
            shortcutsSub.addItem(mi)
        }
        shortcutsSub.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Shortcuts…", action: #selector(showWindow), keyEquivalent: "")
        edit.target = self
        shortcutsSub.addItem(edit)
        shortcutsItem.submenu = shortcutsSub
        menu.addItem(shortcutsItem)

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

        // Tint explicitly rather than relying on template auto-tinting: the
        // status-bar button resolves to VibrantLight even when the menu bar is
        // dark, which would draw the glyph black. Follow the *system* appearance
        // (not the app's Light/Dark preference, which only governs the window).
        button.contentTintColor = Self.systemPrefersDark ? .white : .black
    }

    /// Reads the global appearance, independent of any NSApp.appearance override.
    private static var systemPrefersDark: Bool {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"]
            as? String == "Dark"
    }

    /// Keep the menu-bar glyph correct when the user flips the system theme.
    private func observeSystemAppearanceChanges() {
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusIcon() }
        }
    }

    // MARK: - Actions

    @objc private func resetTapped() { mixer.resetAll(); updateStatusIcon() }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let nowEnabled = LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = nowEnabled ? .on : .off
    }

    @objc private func setAppearanceMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = AppearanceMode(rawValue: raw) else { return }
        mixer.setAppearance(mode)
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
