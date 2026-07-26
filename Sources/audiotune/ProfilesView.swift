import SwiftUI

/// Profiles tab — save the current mix as a named preset ("Work", "Gaming",
/// "Streaming"), switch between them, and bind a shortcut to each.
struct ProfilesView: View {
    @ObservedObject var mixer: AudioMixer
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    createSection
                    listSection
                }
                .padding(20)
            }
        }
    }

    // MARK: - Create

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEW PRESET")
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                TextField("Name (e.g. Work, Gaming, Streaming)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                Button("Save current mix", action: create)
                    .disabled(trimmedName.isEmpty)
            }

            Text("Captures every app's current volume and the master level.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        mixer.createProfile(named: name)
        newName = ""
    }

    // MARK: - List

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRESETS")
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)

            defaultRow
            Divider()

            if mixer.profiles.isEmpty {
                Text("No presets yet. Set your levels in the Mixer tab, then save them above.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(mixer.profiles) { profile in
                    profileRow(profile)
                    if profile.id != mixer.profiles.last?.id { Divider() }
                }
            }
        }
    }

    private var defaultRow: some View {
        HStack(spacing: 10) {
            Image(systemName: mixer.activeProfileID == nil ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(mixer.activeProfileID == nil ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Default").font(.body.weight(.medium))
                Text("Manual levels — no preset applied")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            KeyRecorder(combo: mixer.combo(for: .activateDefault), width: 84) {
                mixer.setCombo($0, for: .activateDefault)
            }

            Button("Use") { mixer.activateDefault() }
                .disabled(mixer.activeProfileID == nil)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func profileRow(_ profile: Profile) -> some View {
        let isActive = mixer.activeProfileID == profile.id

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                if renaming == profile.id {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitRename(profile) }
                    Button("Done") { commitRename(profile) }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name).font(.body.weight(.medium))
                        Text(summary(profile)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()

                    KeyRecorder(combo: mixer.combo(for: .activateProfile(profile.id)), width: 84) {
                        mixer.setCombo($0, for: .activateProfile(profile.id))
                    }

                    Button("Apply") { mixer.activateProfile(id: profile.id) }

                    Menu {
                        Button("Update from current levels") {
                            mixer.updateProfileFromCurrent(id: profile.id)
                        }
                        Button("Rename") {
                            renameText = profile.name
                            renaming = profile.id
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            mixer.deleteProfile(id: profile.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func commitRename(_ profile: Profile) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { mixer.renameProfile(id: profile.id, to: name) }
        renaming = nil
    }

    private func summary(_ profile: Profile) -> String {
        let n = profile.apps.count
        let masterPct = Int((profile.master.effectiveGain * 100).rounded())
        let appsPart = n == 0 ? "no app overrides" : "\(n) app\(n == 1 ? "" : "s")"
        return "\(appsPart) · master \(masterPct)%"
    }
}
