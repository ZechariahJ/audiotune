// Renders a demo GIF of the AudioTune window: Photos' volume drags down while
// Music and Safari stay at 100% — the per-app pitch in one motion.
// Frames are rendered off-screen with SwiftUI's ImageRenderer (crisp, no screen
// capture) and encoded to an animated GIF via ImageIO. No external tools.
//
// Usage: swift tools/makegif.swift <output.gif> [framesDir]
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo.gif"
let framesDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

func appIcon(_ bundleID: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

let musicIcon = appIcon("com.apple.Music")
let photosIcon = appIcon("com.apple.Photos")
let safariIcon = appIcon("com.apple.Safari")

// MARK: - Demo UI (mirrors MixerView, solid backgrounds so it encodes cleanly)

struct DemoRow: View {
    let name: String
    let icon: NSImage?
    let value: Double
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            (icon.map { Image(nsImage: $0).resizable() } ?? Image(systemName: "app.dashed").resizable())
                .interpolation(.high)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body).foregroundStyle(.primary)
                Text("Playing").font(.caption2).foregroundStyle(.green)
            }
            .frame(width: 92, alignment: .leading)

            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.secondary).frame(width: 16)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4)
                    Capsule().fill(Color.accentColor)
                        .frame(width: max(8, geo.size.width * value), height: 4)
                    Circle().fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .overlay(Circle().stroke(Color.black.opacity(0.08)))
                        .offset(x: max(0, min(geo.size.width - 16, geo.size.width * value - 8)))
                }
            }
            .frame(height: 16)

            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(emphasized ? Color.accentColor : .secondary)
                .frame(width: 40, alignment: .trailing)

            Image(systemName: "pin")
                .foregroundStyle(.tertiary).frame(width: 16)
        }
        .padding(.vertical, 7)
    }
}

struct DemoWindow: View {
    let photos: Double

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            ZStack {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.35)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.24, green: 0.79, blue: 0.29)).frame(width: 12, height: 12)
                    Spacer()
                }
                Text("AudioTune").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).frame(height: 38)
            .background(Color(nsColor: .windowBackgroundColor))

            // Master row
            HStack(spacing: 14) {
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Apps").font(.headline)
                    Text("Master volume").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary).frame(width: 16)
                ZStack(alignment: .trailing) {
                    Capsule().fill(Color.accentColor).frame(width: 140, height: 4)
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .overlay(Circle().stroke(Color.black.opacity(0.08)))
                }
                Text("100%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Color(white: 0.95))

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("PLAYING").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .padding(.leading, 20).padding(.top, 12).padding(.bottom, 2)
                DemoRow(name: "Music", icon: musicIcon, value: 1.0).padding(.horizontal, 20)
                Divider().padding(.leading, 58)
                DemoRow(name: "Photos", icon: photosIcon, value: photos, emphasized: photos < 0.99).padding(.horizontal, 20)
                Divider().padding(.leading, 58)
                DemoRow(name: "Safari", icon: safariIcon, value: 1.0).padding(.horizontal, 20)
            }
            .padding(.bottom, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Footer
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(["System", "Light", "Dark"], id: \.self) { seg in
                        Text(seg).font(.caption)
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                            .background(seg == "System" ? Color.accentColor : Color.clear)
                            .foregroundStyle(seg == "System" ? Color.white : Color.secondary)
                    }
                }
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Label("Reset all", systemImage: "arrow.counterclockwise")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text("Launch at Login").font(.callout).foregroundStyle(.secondary)
                    Capsule().fill(Color.green).frame(width: 26, height: 15)
                        .overlay(Circle().fill(.white).frame(width: 11, height: 11).offset(x: 5))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color(white: 0.95))
        }
        .frame(width: 430)
        .environment(\.colorScheme, .light)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Frame timeline

struct FrameSpec { let photos: Double; let delay: Double }

func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }

var specs: [FrameSpec] = []
specs.append(FrameSpec(photos: 1.0, delay: 1.0))          // hold full
let down = 26
for i in 1...down {                                        // drag down 100% -> 18%
    let v = 1.0 - 0.82 * smoothstep(Double(i) / Double(down))
    specs.append(FrameSpec(photos: v, delay: 0.045))
}
specs.append(FrameSpec(photos: 0.18, delay: 1.3))          // hold low
let up = 18
for i in 1...up {                                          // ease back to 100%
    let v = 0.18 + 0.82 * smoothstep(Double(i) / Double(up))
    specs.append(FrameSpec(photos: v, delay: 0.045))
}
specs.append(FrameSpec(photos: 1.0, delay: 0.6))           // brief hold before loop

// MARK: - Render + encode

@MainActor
func generate() {
    let scale: CGFloat = 2
    var images: [(CGImage, Double)] = []
    if let dir = framesDir { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }

    for (idx, spec) in specs.enumerated() {
        let renderer = ImageRenderer(content: DemoWindow(photos: spec.photos))
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else { continue }
        images.append((cg, spec.delay))
        if let dir = framesDir, [0, down / 2, down + 1].contains(idx) {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "\(dir)/frame_\(idx).png"))
            }
        }
    }

    let url = URL(fileURLWithPath: outPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil) else {
        print("failed to create destination"); return
    }
    let gifProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
    CGImageDestinationSetProperties(dest, gifProps as CFDictionary)
    for (cg, delay) in images {
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]]
        CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
    }
    if CGImageDestinationFinalize(dest) {
        print("wrote \(outPath) with \(images.count) frames")
    } else {
        print("failed to finalize gif")
    }
}

MainActor.assumeIsolated { generate() }
