import AppKit
import ImageIO

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.icns")
guard let encoder = CGImageDestinationCreateWithURL(output as CFURL, "com.apple.icns" as CFString, 10, nil) else {
    fatalError("System ICNS encoder unavailable")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        // Explicit pixels avoid dependence on the build host's Retina scaling.
        guard let context = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                      bytesPerRow: px * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Cannot create icon bitmap")
        }
        context.clear(CGRect(x: 0, y: 0, width: px, height: px))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let s = CGFloat(size)
        let rect = NSRect(x: 0, y: 0, width: s, height: s)
        let background = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.04, dy: s * 0.04), xRadius: s * 0.22, yRadius: s * 0.22)
        NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.22, blue: 0.28, alpha: 1), ending: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1))!.draw(in: background, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        let top = NSBezierPath(rect: NSRect(x: 0, y: s * 0.42, width: s, height: s))
        top.addClip()
        let sun = NSBezierPath(ovalIn: NSRect(x: s * 0.24, y: s * 0.24, width: s * 0.52, height: s * 0.52))
        NSGradient(starting: NSColor(calibratedRed: 1, green: 0.85, blue: 0.50, alpha: 1), ending: NSColor(calibratedRed: 1, green: 0.48, blue: 0.25, alpha: 1))!.draw(in: sun, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        for (offset, width) in [(0.0, 0.60), (-0.095, 0.44), (-0.19, 0.24)] {
            NSColor(calibratedRed: 1, green: 0.70, blue: 0.39, alpha: 1).setStroke()
            let line = NSBezierPath(); line.lineWidth = s * 0.034; line.lineCapStyle = .round
            line.move(to: NSPoint(x: s * (0.5 - width / 2), y: s * (0.42 + offset)))
            line.line(to: NSPoint(x: s * (0.5 + width / 2), y: s * (0.42 + offset))); line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { fatalError("Cannot export icon bitmap") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = NSSize(width: size, height: size)
        let suffix = scale == 2 ? "@2x" : ""
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        // ImageIO supplies the legacy 16/32px RGB+alpha-mask records and TOC,
        // in addition to the modern Retina representations.
        CGImageDestinationAddImage(encoder, image,
            [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
    }
}
guard CGImageDestinationFinalize(encoder) else { fatalError("System ICNS encoding failed") }
