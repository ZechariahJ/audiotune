// Renders AudioTune's app icon at every required size into an .iconset folder.
// Usage: swift tools/makeicon.swift <output.iconset dir>
// A native macOS squircle with a blue→violet gradient and the slider glyph.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AudioTune.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(px: Int) -> Data {
    let S = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    cg.clear(CGRect(x: 0, y: 0, width: S, height: S))

    // Squircle matching Apple's icon grid (~0.098 margin, ~0.225 corner ratio).
    let margin = S * 0.098
    let rect = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let radius = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    cg.setFillColor(NSColor.black.cgColor)
    cg.fill(rect)
    cg.restoreGState()

    // White slider glyph, centered, with a soft drop shadow.
    let config = NSImage.SymbolConfiguration(pointSize: S * 0.46, weight: .bold)
    if let sym = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        sym.isTemplate = true
        let g = sym.size
        var gr = CGRect(x: (S - g.width) / 2, y: (S - g.height) / 2, width: g.width, height: g.height)
        if let cgImg = sym.cgImage(forProposedRect: &gr, context: ctx, hints: nil) {
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -S * 0.008), blur: S * 0.02,
                         color: NSColor(white: 0, alpha: 0.25).cgColor)
            cg.clip(to: gr, mask: cgImg)
            cg.setFillColor(NSColor.white.cgColor)
            cg.fill(gr)
            cg.restoreGState()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let targets: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in targets {
    let data = drawIcon(px: px)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    try! data.write(to: url)
    print("wrote \(name).png (\(px)px)")
}
