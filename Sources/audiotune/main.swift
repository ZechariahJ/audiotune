import AppKit

// Entry point. Starts as an accessory app: menu-bar item only, no Dock icon and
// no Cmd-Tab entry while it's just running in the background. Opening the window
// promotes it to a regular app (Dock icon appears); closing the window demotes
// it again. See AppDelegate.showWindow / windowWillClose.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
