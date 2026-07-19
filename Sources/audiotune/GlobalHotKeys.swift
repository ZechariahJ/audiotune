import AppKit
import Carbon

/// Registers system-wide hotkeys via Carbon's RegisterEventHotKey (works
/// everywhere, needs no Accessibility permission). Actions run on the main actor.
/// Carbon hotkeys fire once on press and don't auto-repeat, so for `repeats`
/// bindings we drive our own repeat timer between the press and release events.
/// @unchecked Sendable: all state is touched only on the main thread.
final class GlobalHotKeys: @unchecked Sendable {
    struct Binding {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let repeats: Bool
        let action: @MainActor () -> Void
    }

    // Repeat cadence: a short delay before repeating, then a steady tick.
    private let repeatDelay: TimeInterval = 0.4
    private let repeatInterval: TimeInterval = 0.1

    private var bindings: [UInt32: Binding] = [:]
    private var repeatTimers: [UInt32: Timer] = [:]
    private var repeatStarts: [UInt32: DispatchWorkItem] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x4154_5548 // 'ATUH'

    func register(_ bindings: [Binding]) {
        installHandlerIfNeeded()
        for b in bindings {
            self.bindings[b.id] = b
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: signature, id: b.id)
            let status = RegisterEventHotKey(b.keyCode, b.modifiers, hkID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                hotKeyRefs.append(ref)
            } else {
                Log.msg("GlobalHotKeys: failed to register id \(b.id) (status \(status)) — likely a conflict")
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 2, &specs, ctx, &eventHandlerRef)
    }

    fileprivate func fire(_ id: UInt32, kind: UInt32) {
        // Carbon delivers hot-key events on the main thread.
        MainActor.assumeIsolated {
            guard let b = bindings[id] else { return }
            if kind == UInt32(kEventHotKeyPressed) {
                b.action()
                if b.repeats { beginRepeat(b) }
            } else if kind == UInt32(kEventHotKeyReleased) {
                endRepeat(id)
            }
        }
    }

    private func beginRepeat(_ b: Binding) {
        endRepeat(b.id)
        let start = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var ticks = 0
            let timer = Timer(timeInterval: self.repeatInterval, repeats: true) { t in
                ticks += 1
                if ticks > 120 { t.invalidate(); return } // ~12s safety cap if a release is ever missed
                MainActor.assumeIsolated { b.action() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.repeatTimers[b.id] = timer
        }
        repeatStarts[b.id] = start
        DispatchQueue.main.asyncAfter(deadline: .now() + repeatDelay, execute: start)
    }

    private func endRepeat(_ id: UInt32) {
        repeatStarts[id]?.cancel()
        repeatStarts[id] = nil
        repeatTimers[id]?.invalidate()
        repeatTimers[id] = nil
    }

    deinit {
        for timer in repeatTimers.values { timer.invalidate() }
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

/// C trampoline — must not capture context; the GlobalHotKeys instance is passed
/// through userData.
private func hotKeyEventHandler(_ next: EventHandlerCallRef?,
                               _ event: EventRef?,
                               _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hkID = EventHotKeyID()
    let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                EventParamType(typeEventHotKeyID), nil,
                                MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    if err == noErr {
        let kind = GetEventKind(event)
        Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue().fire(hkID.id, kind: kind)
    }
    return noErr
}
