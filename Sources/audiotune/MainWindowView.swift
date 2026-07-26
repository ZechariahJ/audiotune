import SwiftUI

/// The window's tab container: the mixer, saved presets, and shortcut editing.
struct MainWindowView: View {
    @ObservedObject var mixer: AudioMixer

    enum Tab: Hashable { case mixer, profiles, shortcuts }
    @State private var selection: Tab = .mixer

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                MixerView(mixer: mixer)
                    .tabItem { Label("Mixer", systemImage: "slider.vertical.3") }
                    .tag(Tab.mixer)

                ProfilesView(mixer: mixer)
                    .tabItem { Label("Presets", systemImage: "square.stack.3d.up.fill") }
                    .tag(Tab.profiles)

                ShortcutsView(mixer: mixer)
                    .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                    .tag(Tab.shortcuts)
            }

            Divider()
            // One footer below the tabs, so it's identical on all three.
            WindowFooter(mixer: mixer)
        }
        .frame(minWidth: 460, minHeight: 480)
    }
}
