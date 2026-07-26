import SwiftUI

/// The window's persistent bottom bar, shared by every tab: reset, appearance,
/// and launch-at-login all on one row.
struct WindowFooter: View {
    @ObservedObject var mixer: AudioMixer
    @State private var launchAtLogin = LoginItem.isEnabled

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(get: { mixer.appearance }, set: { mixer.setAppearance($0) })
    }

    var body: some View {
        // The picker is centred in a ZStack so it stays on the window's midline
        // regardless of how wide the two side controls are.
        ZStack {
            Picker("Appearance", selection: appearanceBinding) {
                ForEach(AppearanceMode.allCases) {
                    Text($0.label).font(.system(size: 12, weight: .semibold)).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 196)

            HStack(spacing: 12) {
                Button {
                    mixer.resetAll()
                } label: {
                    Label("Reset all", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Return every app and the master to 100%")

                Spacer(minLength: 0)

                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at Login").font(.system(size: 13, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
                .onChange(of: launchAtLogin) { _, newValue in
                    launchAtLogin = LoginItem.setEnabled(newValue)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
