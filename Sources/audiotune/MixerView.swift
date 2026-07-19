import SwiftUI

/// The full windowed interface. Mirrors the menu-bar controls with more room.
struct MixerView: View {
    @ObservedObject var mixer: AudioMixer
    @State private var launchAtLogin = LoginItem.isEnabled

    private var playing: [AudioMixer.MixerApp] { mixer.apps.filter { $0.isPlaying || $0.settings.pinned } }
    private var others: [AudioMixer.MixerApp] { mixer.apps.filter { !($0.isPlaying || $0.settings.pinned) } }

    var body: some View {
        VStack(spacing: 0) {
            masterHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(title: "Playing", apps: playing,
                            empty: "No apps are playing audio.")
                    if !others.isEmpty {
                        section(title: "All apps", apps: others, empty: nil)
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 480, idealHeight: 560)
    }

    // MARK: - Master

    private var masterHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("All Apps")
                    .font(.headline)
                Text("Master volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VolumeControls(
                gain: mixer.master.gain,
                muted: mixer.master.muted,
                onGain: { mixer.setMasterGain($0) },
                onMute: { mixer.toggleMasterMute() }
            )
            .frame(width: 190)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.regularMaterial)
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(title: String, apps: [AudioMixer.MixerApp], empty: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            if apps.isEmpty, let empty {
                Text(empty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(apps) { app in
                        AppRow(app: app, mixer: mixer)
                        if app.id != apps.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                mixer.resetAll()
            } label: {
                Label("Reset all", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)

            Spacer()

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: launchAtLogin) { _, newValue in
                    launchAtLogin = LoginItem.setEnabled(newValue)
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

/// One app's row: icon, name, slider, mute, pin.
private struct AppRow: View {
    let app: AudioMixer.MixerApp
    let mixer: AudioMixer

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)
                if app.isPlaying {
                    Text("Playing")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 96, alignment: .leading)

            VolumeControls(
                gain: app.settings.gain,
                muted: app.settings.muted,
                onGain: { mixer.setGain(app.key, app.name, $0) },
                onMute: { mixer.toggleMute(app.key, app.name) }
            )

            Button {
                mixer.togglePin(app.key)
            } label: {
                Image(systemName: app.settings.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(app.settings.pinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(app.settings.pinned ? "Unpin" : "Keep in the main list")
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = app.icon {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
        }
    }
}

/// Shared mute button + slider + percent readout, used by app rows and master.
private struct VolumeControls: View {
    let gain: Float
    let muted: Bool
    let onGain: (Float) -> Void
    let onMute: () -> Void

    private var binding: Binding<Double> {
        Binding(get: { Double(gain) }, set: { onGain(Float($0)) })
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onMute) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(muted ? Color.red : Color.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(muted ? "Unmute" : "Mute")

            Slider(value: binding, in: 0...1)
                .controlSize(.small)
                .opacity(muted ? 0.4 : 1)

            Text(muted ? "Muted" : "\(Int((gain * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
