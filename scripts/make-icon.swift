#!/usr/bin/env swift
// Renders the DockShift app icon at every size macOS wants and packs it into
// Resources/AppIcon.icns. Needs only the Command Line Tools:
//
//   swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("DockShift.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

func draw(size: CGFloat) -> NSImage {
    let s = size / 1024
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let canvas = NSRect(x: 0, y: 0, width: size, height: size)

        // macOS icon squircle with a vertical gradient.
        let inset = 60 * s
        let squircle = NSBezierPath(roundedRect: canvas.insetBy(dx: inset, dy: inset), xRadius: 210 * s, yRadius: 210 * s)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.17, blue: 0.52, alpha: 1),
        ])!.draw(in: squircle, angle: -90)

        // Soft highlight at the top.
        NSGraphicsContext.current?.saveGraphicsState()
        squircle.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.22)])!
            .draw(in: NSRect(x: 0, y: size * 0.45, width: size, height: size * 0.55), angle: 90)
        NSGraphicsContext.current?.restoreGraphicsState()

        // The Dock tray.
        let tray = NSRect(x: 150 * s, y: 250 * s, width: 724 * s, height: 232 * s)
        let trayPath = NSBezierPath(roundedRect: tray, xRadius: 56 * s, yRadius: 56 * s)
        NSColor.white.withAlphaComponent(0.18).setFill()
        trayPath.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        trayPath.lineWidth = 6 * s
        trayPath.stroke()

        // Four app tiles; the second is lifted to suggest a switch.
        let tileColors: [NSColor] = [
            NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.26, alpha: 1),
            NSColor(calibratedRed: 0.36, green: 0.85, blue: 0.56, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.62, green: 0.74, blue: 1.00, alpha: 1),
        ]
        let tileSize = 150 * s
        let gap = 34 * s
        let totalWidth = tileSize * 4 + gap * 3
        var x = tray.midX - totalWidth / 2
        for (index, color) in tileColors.enumerated() {
            let lift: CGFloat = index == 1 ? 150 * s : 0
            let rect = NSRect(x: x, y: tray.minY + 41 * s + lift, width: tileSize, height: tileSize)
            if index == 1 {
                NSColor.black.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: -10 * s), xRadius: 36 * s, yRadius: 36 * s).fill()
            }
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 36 * s, yRadius: 36 * s).fill()
            x += tileSize + gap
        }

        // Dot under the lifted tile: it is "running".
        NSColor.white.withAlphaComponent(0.9).setFill()
        let dotX = tray.midX - totalWidth / 2 + tileSize + gap + tileSize / 2
        NSBezierPath(ovalIn: NSRect(x: dotX - 9 * s, y: tray.minY + 12 * s, width: 18 * s, height: 18 * s)).fill()
        return true
    }
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try png(draw(size: CGFloat(pixels)), pixels: pixels).write(to: iconset.appendingPathComponent(name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("Wrote \(output.path)")
