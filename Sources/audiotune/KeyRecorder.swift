import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A click-to-record shortcut field. While recording it swallows key events so
/// the next combo you press becomes the binding. Escape cancels; a combo must
/// include at least one modifier (otherwise plain letters would be captured
/// system-wide).
struct KeyRecorder: View {
    let combo: HotkeyCombo?
    var width: CGFloat = 96
    let onChange: (HotkeyCombo?) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(label)
                    .font(.system(size: 12, weight: recording ? .semibold : .regular))
                    .foregroundStyle(recording ? Color.accentColor : (combo == nil ? .secondary : .primary))
                    .frame(width: width)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .help(recording ? "Press a shortcut, or Escape to cancel" : "Click to record a shortcut")

            Button {
                stop()
                onChange(nil)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .opacity(combo == nil ? 0 : 1)
            .disabled(combo == nil)
            .help("Clear shortcut")
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return "Press keys…" }
        return combo?.display ?? "Not set"
    }

    private func toggle() {
        if recording { stop() } else { start() }
    }

    private func start() {
        guard monitor == nil else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil } // swallow modifier-only events
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let mods = Self.carbonModifiers(event.modifierFlags)
            let candidate = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            guard candidate.hasModifiers else { return nil } // ignore bare keys
            stop()
            onChange(candidate)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }
}
