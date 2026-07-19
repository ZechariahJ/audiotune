import AppKit
import Carbon

/// Registers system-wide hotkeys via Carbon's RegisterEventHotKey (works
/// everywhere, needs no Accessibility permission). Actions run on the main actor.
/// @unchecked Sendable: all state is touched only on the main thread (register at
/// launch, fire from Carbon's main-thread event delivery).
final class GlobalHotKeys: @unchecked Sendable {
    struct Binding {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let action: @MainActor () -> Void
    }

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x4154_5548 // 'ATUH'

    func register(_ bindings: [Binding]) {
        installHandlerIfNeeded()
        for b in bindings {
            handlers[b.id] = b.action
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
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, ctx, &eventHandlerRef)
    }

    fileprivate func fire(_ id: UInt32) {
        // Carbon delivers hot-key events on the main thread.
        MainActor.assumeIsolated { handlers[id]?() }
    }

    deinit {
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
        Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue().fire(hkID.id)
    }
    return noErr
}
