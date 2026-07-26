import SwiftUI

/// Shortcuts tab — rebind the global actions and assign per-app shortcuts.
/// All shortcuts are system-wide: they work whatever app you're in.
struct ShortcutsView: View {
    @ObservedObject var mixer: AudioMixer
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    globalSection
                    perAppSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
    }

    // MARK: - Global

    private var globalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GLOBAL")
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)

            ForEach(HotkeyAction.globalActions, id: \.storageID) { action in
                HStack {
                    Text(action.globalLabel ?? "")
                        .font(.body)
                    Spacer()
                    KeyRecorder(combo: mixer.combo(for: action)) {
                        mixer.setCombo($0, for: action)
                    }
                }
                .padding(.vertical, 3)
            }

            Text("Volume shortcuts move in 5% steps and repeat while held.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Per-app

    private var filteredApps: [AudioMixer.MixerApp] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return mixer.apps }
        return mixer.apps.filter { $0.name.lowercased().contains(q) }
    }

    private var perAppSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PER-APP")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                Spacer()
                TextField("Filter", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
            }

            HStack(spacing: 8) {
                Text("").frame(width: 150, alignment: .leading)
                Text("Raise").font(.caption2).foregroundStyle(.tertiary).frame(width: 96)
                Text("Lower").font(.caption2).foregroundStyle(.tertiary).frame(width: 96)
                Text("Mute").font(.caption2).foregroundStyle(.tertiary).frame(width: 96)
            }

            if filteredApps.isEmpty {
                Text("No apps match.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(filteredApps) { app in
                    appRow(app)
                    if app.id != filteredApps.last?.id { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private func appRow(_ app: AudioMixer.MixerApp) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                (app.icon.map { Image(nsImage: $0).resizable() }
                    ?? Image(systemName: "app.dashed").resizable())
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                Text(app.name).font(.callout).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            KeyRecorder(combo: mixer.combo(for: .appVolumeUp(app.key)), width: 72) {
                mixer.setCombo($0, for: .appVolumeUp(app.key))
            }
            KeyRecorder(combo: mixer.combo(for: .appVolumeDown(app.key)), width: 72) {
                mixer.setCombo($0, for: .appVolumeDown(app.key))
            }
            KeyRecorder(combo: mixer.combo(for: .appMute(app.key)), width: 72) {
                mixer.setCombo($0, for: .appMute(app.key))
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                mixer.resetHotkeys()
            } label: {
                Label("Restore defaults", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("Shortcuts need a modifier (⌃ ⌥ ⇧ ⌘)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}
