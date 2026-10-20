import Foundation

struct Preferences: Codable {
    var enabled = false
    var scheduled = false
    var kelvin = 4200.0
    var brightness = 0.90
    var startMinute = 21 * 60
    var endMinute = 7 * 60
    var rampMinutes = 30.0

    mutating func sanitize() {
        kelvin = kelvin.isFinite ? min(6500, max(2700, kelvin)) : 4200
        brightness = brightness.isFinite ? min(1, max(0.30, brightness)) : 0.90
        startMinute = ((startMinute % 1440) + 1440) % 1440
        endMinute = ((endMinute % 1440) + 1440) % 1440
        rampMinutes = rampMinutes.isFinite ? min(120, max(0, rampMinutes)) : 30
    }

    func strength(at date: Date, calendar: Calendar = .current) -> Double {
        if !enabled { return 0 }
        if !scheduled { return 1 }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Schedule.strength(minute: Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60,
                                 start: startMinute, end: endMinute, ramp: rampMinutes)
    }
}

enum Schedule {
    // Local wall-clock minutes keep the schedule aligned after DST/timezone changes.
    static func strength(minute: Double, start: Int, end: Int, ramp: Double) -> Double {
        let duration = Double((end - start + 1440) % 1440)
        guard duration > 0 else { return 0 }
        let elapsed = (minute - Double(start) + 1440).truncatingRemainder(dividingBy: 1440)
        guard elapsed < duration else { return 0 }
        let fade = min(max(0, ramp), duration / 2)
        guard fade > 0 else { return 1 }
        let linear = min(1, min(elapsed / fade, (duration - elapsed) / fade))
        return linear * linear * (3 - 2 * linear)
    }
    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

struct Gains: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    static let identity = Gains(red: 1, green: 1, blue: 1)
    static func mix(_ a: Gains, _ b: Gains, fraction: Double) -> Gains {
        let t = min(1, max(0, fraction))
        return Gains(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t,
                     blue: a.blue + (b.blue - a.blue) * t)
    }
    static func temperature(_ kelvin: Double, brightness: Double, strength: Double) -> Gains {
        let t = min(6500, max(2700, kelvin)) / 100
        let green = min(1, max(0, (99.4708025861 * log(t) - 161.1195681661) / 255))
        let blue = min(1, max(0, (138.5177312231 * log(t - 10) - 305.0447927307) / 255))
        let referenceGreen = (99.4708025861 * log(65) - 161.1195681661) / 255
        let referenceBlue = (138.5177312231 * log(55) - 305.0447927307) / 255
        let b = min(1, max(0.30, brightness))
        let warm = Gains(red: b, green: min(1, green / referenceGreen) * b, blue: min(1, blue / referenceBlue) * b)
        return mix(.identity, warm, fraction: strength)
    }
    func transform(_ values: [Float], channel: Double) -> [Float] {
        values.map { min(1, max(0, $0 * Float(channel))) }
    }
}
