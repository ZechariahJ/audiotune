import Foundation

/// Per-app audio preferences, keyed by a stable app identity (bundle id).
struct AppAudioSettings: Codable, Equatable {
    var gain: Float = 1.0
    var muted: Bool = false
    var pinned: Bool = false

    var isDefault: Bool { gain == 1.0 && !muted && !pinned }
    /// The value the render callback should apply right now.
    var effectiveGain: Float { muted ? 0 : gain }
}

/// Persists per-app settings across launches via UserDefaults (JSON blob).
@MainActor
final class SettingsStore {
    private let defaultsKey = "appAudioSettings.v1"
    private var map: [String: AppAudioSettings] = [:]

    init() { load() }

    func settings(for key: String) -> AppAudioSettings {
        map[key] ?? AppAudioSettings()
    }

    /// Keys with non-default settings — used to auto-attach on launch/playback.
    var customizedKeys: [String] { Array(map.keys) }

    func update(_ key: String, _ mutate: (inout AppAudioSettings) -> Void) {
        var s = map[key] ?? AppAudioSettings()
        mutate(&s)
        if s.isDefault {
            map[key] = nil          // don't persist defaults; keeps the store small
        } else {
            map[key] = s
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: AppAudioSettings].self, from: data)
        else { return }
        map = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
