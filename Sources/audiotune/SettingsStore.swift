import Foundation

/// App-wide appearance preference. `.system` follows the OS (and live-updates).
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Per-app audio preferences, keyed by a stable app identity (bundle id).
struct AppAudioSettings: Codable, Equatable {
    var gain: Float = 1.0
    var muted: Bool = false
    var pinned: Bool = false

    var isDefault: Bool { gain == 1.0 && !muted && !pinned }
    /// The value the render callback should apply for this channel alone.
    var effectiveGain: Float { muted ? 0 : gain }
}

/// Everything we persist between launches.
///
/// Fields added after v2 shipped are Optional on purpose: the synthesized
/// decoder uses `decodeIfPresent` for optionals, so older saved state (which
/// lacks these keys) still decodes cleanly instead of throwing.
private struct PersistedState: Codable {
    var apps: [String: AppAudioSettings] = [:]
    var master = AppAudioSettings()
    var profiles: [Profile]?
    var activeProfileID: String?
    var hotkeys: [HotkeyBinding]?
}

/// Persists per-app + master settings across launches via UserDefaults (JSON).
@MainActor
final class SettingsStore {
    private let defaultsKey = "audiotuneState.v2"
    private let appearanceKey = "audiotuneAppearance" // stored separately to avoid state migration
    private var state = PersistedState()

    init() { load() }

    // MARK: - Appearance

    var appearance: AppearanceMode {
        get { UserDefaults.standard.string(forKey: appearanceKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey) }
    }

    // MARK: - Per-app

    func settings(for key: String) -> AppAudioSettings {
        state.apps[key] ?? AppAudioSettings()
    }

    func update(_ key: String, _ mutate: (inout AppAudioSettings) -> Void) {
        var s = state.apps[key] ?? AppAudioSettings()
        mutate(&s)
        if s.isDefault {
            state.apps[key] = nil       // don't persist defaults; keeps the store small
        } else {
            state.apps[key] = s
        }
        save()
    }

    // MARK: - Master channel

    var master: AppAudioSettings { state.master }

    func updateMaster(_ mutate: (inout AppAudioSettings) -> Void) {
        mutate(&state.master)
        state.master.pinned = false     // pinning is meaningless for master
        save()
    }

    // MARK: - Profiles

    var profiles: [Profile] { state.profiles ?? [] }
    var activeProfileID: String? { state.activeProfileID }

    func profile(id: String) -> Profile? { profiles.first { $0.id == id } }

    func addProfile(_ profile: Profile) {
        var list = profiles
        list.append(profile)
        state.profiles = list
        save()
    }

    func updateProfile(_ profile: Profile) {
        guard var list = state.profiles, let i = list.firstIndex(where: { $0.id == profile.id }) else { return }
        list[i] = profile
        state.profiles = list
        save()
    }

    func deleteProfile(id: String) {
        state.profiles = profiles.filter { $0.id != id }
        if state.activeProfileID == id { state.activeProfileID = nil }
        // Drop any shortcut that pointed at the deleted profile.
        state.hotkeys = hotkeyBindings.filter { $0.action != .activateProfile(id) }
        save()
    }

    func setActiveProfile(_ id: String?) {
        state.activeProfileID = id
        save()
    }

    /// Overwrite live volume state with a profile's levels. Pins are preserved
    /// (they're a UI preference, not part of the audio snapshot).
    func applyProfile(_ profile: Profile) {
        var next: [String: AppAudioSettings] = [:]
        // Keep existing pins for every app we know about.
        for (key, existing) in state.apps where existing.pinned {
            next[key] = AppAudioSettings(gain: 1.0, muted: false, pinned: true)
        }
        for (key, s) in profile.apps {
            var merged = s
            merged.pinned = next[key]?.pinned ?? state.apps[key]?.pinned ?? false
            next[key] = merged.isDefault ? nil : merged
        }
        state.apps = next
        state.master = profile.master
        state.activeProfileID = profile.id
        save()
    }

    /// Snapshot the current volume state (ignoring pins) as a profile's levels.
    func currentAsSnapshot() -> (apps: [String: AppAudioSettings], master: AppAudioSettings) {
        var apps: [String: AppAudioSettings] = [:]
        for (key, s) in state.apps where !(s.gain == 1.0 && !s.muted) {
            apps[key] = AppAudioSettings(gain: s.gain, muted: s.muted, pinned: false)
        }
        return (apps, state.master)
    }

    // MARK: - Hotkeys

    /// User bindings, seeded with the shipping defaults on first run.
    var hotkeyBindings: [HotkeyBinding] { state.hotkeys ?? HotkeyBinding.defaults }

    func setCombo(_ combo: HotkeyCombo?, for action: HotkeyAction) {
        var list = hotkeyBindings.filter { $0.action != action }
        // A combo can only drive one action; clear any other binding using it.
        if let combo {
            list.removeAll { $0.combo == combo }
            list.append(HotkeyBinding(action: action, combo: combo))
        }
        state.hotkeys = list
        save()
    }

    /// Reset the shortcuts owned by the Shortcuts tab (global + per-app) back to
    /// the shipping defaults. Preset-activation shortcuts are managed in the
    /// Presets tab, so they're deliberately left alone.
    func resetHotkeysToDefaults() {
        let preserved = hotkeyBindings.filter { binding in
            switch binding.action {
            case .activateProfile, .activateDefault: return true
            default: return false
            }
        }
        state.hotkeys = HotkeyBinding.defaults + preserved
        save()
    }

    // MARK: - Reset

    /// Return every app and the master to full volume / unmuted, keeping pins.
    func resetVolumes() {
        for key in state.apps.keys {
            state.apps[key]?.gain = 1.0
            state.apps[key]?.muted = false
            if state.apps[key]?.isDefault == true { state.apps[key] = nil }
        }
        state.master.gain = 1.0
        state.master.muted = false
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }
        state = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
