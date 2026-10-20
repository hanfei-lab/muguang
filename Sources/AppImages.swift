import AppKit

// Resolution-independent drawing works on Catalina without SF Symbols.
enum AppImages {
    static func sun(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            (template ? NSColor.black : NSColor(calibratedRed: 1, green: 0.73, blue: 0.38, alpha: 1)).set()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: s * 0.40, width: s, height: s)).addClip()
            NSBezierPath(ovalIn: NSRect(x: s * 0.23, y: s * 0.22, width: s * 0.54, height: s * 0.54)).fill()
            NSGraphicsContext.restoreGraphicsState()
            for (y, width) in [(0.36, 0.78), (0.21, 0.55)] {
                let line = NSBezierPath(); line.lineWidth = max(1, s * 0.075); line.lineCapStyle = .round
                line.move(to: NSPoint(x: s * (0.5 - width / 2), y: s * y))
                line.line(to: NSPoint(x: s * (0.5 + width / 2), y: s * y)); line.stroke()
            }
            for angle in [45.0, 90.0, 135.0] {
                let theta = angle * .pi / 180
                let ray = NSBezierPath(); ray.lineWidth = max(1, s * 0.065); ray.lineCapStyle = .round
                ray.move(to: NSPoint(x: s * (0.5 + 0.37 * cos(theta)), y: s * (0.49 + 0.37 * sin(theta))))
                ray.line(to: NSPoint(x: s * (0.5 + 0.45 * cos(theta)), y: s * (0.49 + 0.45 * sin(theta)))); ray.stroke()
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "暮光"
        return image
    }
}
