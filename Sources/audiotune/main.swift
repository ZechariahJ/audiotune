import AppKit

// Entry point. Regular app: shows a Dock icon and a menu-bar item. The window
// is created on demand (Dock click, Dock menu, or the menu-bar item), never at
// launch.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
