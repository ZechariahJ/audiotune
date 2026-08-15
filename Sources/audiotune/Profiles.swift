import Foundation
import Carbon.HIToolbox

// MARK: - Profiles

/// A named snapshot of volume state — "Work", "Gaming", "Streaming" — that can
/// be applied in one click. Activating a profile writes its levels over the
/// live state; "Default" (no active profile) is whatever you last set by hand.
struct Profile: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var apps: [String: AppAudioSettings] = [:]
    var master = AppAudioSettings()
    /// When set, this preset is applied automatically the moment this output
    /// device becomes the system default (e.g. plugging in earbuds).
    /// Optional so presets saved before this feature still decode.
    var autoDeviceUID: String?
}

// MARK: - Hotkeys

/// A key combination, stored as Carbon virtual key code + modifier mask so it
/// can be handed straight to RegisterEventHotKey.
struct HotkeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Human-readable form, e.g. "⌃⌥M". Apple's modifier order is ⌃⌥⇧⌘.
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + HotkeyCombo.keyName(keyCode)
    }

    var hasModifiers: Bool {
        modifiers & UInt32(controlKey | optionKey | shiftKey | cmdKey) != 0
    }

    static func keyName(_ code: UInt32) -> String {
        if let name = specialKeys[Int(code)] { return name }
        if let letter = letterKeys[Int(code)] { return letter }
        return "Key \(code)"
    }

    private static let specialKeys: [Int: String] = [
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Escape: "Esc",
        kVK_Delete: "Delete", kVK_ForwardDelete: "Fwd Del", kVK_Home: "Home", kVK_End: "End",
        kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let letterKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
    ]
}

/// Everything a hotkey can be bound to.
enum HotkeyAction: Codable, Hashable {
    case frontmostVolumeUp
    case frontmostVolumeDown
    case frontmostMute
    case masterVolumeUp
    case masterVolumeDown
    case masterMute
    case appVolumeUp(String)     // stable app key (bundle id)
    case appVolumeDown(String)
    case appMute(String)
    case activateProfile(String) // profile id
    case activateDefault

    /// Volume nudges auto-repeat while held; toggles fire once.
    var repeats: Bool {
        switch self {
        case .frontmostVolumeUp, .frontmostVolumeDown,
             .masterVolumeUp, .masterVolumeDown,
             .appVolumeUp, .appVolumeDown:
            return true
        default:
            return false
        }
    }

    /// Stable identity used for dedupe and as a SwiftUI id.
    var storageID: String {
        switch self {
        case .frontmostVolumeUp:      return "frontmost.up"
        case .frontmostVolumeDown:    return "frontmost.down"
        case .frontmostMute:          return "frontmost.mute"
        case .masterVolumeUp:         return "master.up"
        case .masterVolumeDown:       return "master.down"
        case .masterMute:             return "master.mute"
        case .appVolumeUp(let k):     return "app.up.\(k)"
        case .appVolumeDown(let k):   return "app.down.\(k)"
        case .appMute(let k):         return "app.mute.\(k)"
        case .activateProfile(let i): return "profile.\(i)"
        case .activateDefault:        return "profile.default"
        }
    }

    /// Label for the global (non per-app) actions.
    var globalLabel: String? {
        switch self {
        case .frontmostVolumeUp:   return "Raise focused app"
        case .frontmostVolumeDown: return "Lower focused app"
        case .frontmostMute:       return "Mute focused app"
        case .masterVolumeUp:      return "Raise all apps"
        case .masterVolumeDown:    return "Lower all apps"
        case .masterMute:          return "Mute all apps"
        default:                   return nil
        }
    }

    /// The global actions shown in the Shortcuts tab, in display order.
    static let globalActions: [HotkeyAction] = [
        .frontmostVolumeUp, .frontmostVolumeDown, .frontmostMute,
        .masterVolumeUp, .masterVolumeDown, .masterMute,
    ]
}

/// One user-assignable shortcut.
struct HotkeyBinding: Codable, Equatable, Identifiable {
    var action: HotkeyAction
    var combo: HotkeyCombo
    var id: String { action.storageID }
}

extension HotkeyBinding {
    /// Shipping defaults — the shortcuts AudioTune has always had.
    static var defaults: [HotkeyBinding] {
        let ctrlOpt = UInt32(controlKey | optionKey)
        return [
            .init(action: .frontmostVolumeUp,   combo: .init(keyCode: UInt32(kVK_UpArrow), modifiers: ctrlOpt)),
            .init(action: .frontmostVolumeDown, combo: .init(keyCode: UInt32(kVK_DownArrow), modifiers: ctrlOpt)),
            .init(action: .frontmostMute,       combo: .init(keyCode: UInt32(kVK_ANSI_M), modifiers: ctrlOpt)),
        ]
    }
}
