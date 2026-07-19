import AppKit
import SwiftUI

/// A small, non-interactive overlay shown briefly when a global hotkey changes
/// an app's volume — like the system volume HUD, but per-app.
@MainActor
final class VolumeHUD {
    private final class Model: ObservableObject {
        @Published var name = ""
        @Published var icon: NSImage?
        @Published var volume: Float = 1
        @Published var muted = false
    }

    private let model = Model()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(name: String, icon: NSImage?, volume: Float, muted: Bool) {
        model.name = name
        model.icon = icon
        model.volume = volume
        model.muted = muted

        if panel == nil { buildPanel() }
        guard let panel else { return }
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        scheduleHide()
    }

    private func buildPanel() {
        let hosting = NSHostingView(rootView: HUDView(model: model))
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 224, height: 104),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.ignoresMouseEvents = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel = p
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let f = screen?.frame else { return }
        let x = f.midX - panel.frame.width / 2
        let y = f.minY + 130
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let panel = self?.panel else { return }
            panel.animator().alphaValue = 0 // implicit ~0.25s fade
            try? await Task.sleep(for: .seconds(0.3))
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }

    private struct HUDView: View {
        @ObservedObject var model: Model

        var body: some View {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    iconView.frame(width: 22, height: 22)
                    Text(model.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(model.muted ? Color.red : Color.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(model.muted ? Color.secondary : Color.accentColor)
                            .frame(width: max(6, geo.size.width * CGFloat(model.muted ? 0 : model.volume)))
                    }
                }
                .frame(height: 6)

                HStack {
                    Spacer()
                    Text(model.muted ? "Muted" : "\(Int((model.volume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 224)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }

        @ViewBuilder private var iconView: some View {
            if let icon = model.icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
    }
}
