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
private struct PersistedState: Codable {
    var apps: [String: AppAudioSettings] = [:]
    var master = AppAudioSettings()
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
