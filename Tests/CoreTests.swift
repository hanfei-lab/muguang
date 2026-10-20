import Foundation

@main struct CoreTests {
    static func main() throws {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if !value() { fatalError("FAIL: \(name)") }
        }
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.00001 }
        let s = 21 * 60, e = 7 * 60
        expect(Schedule.strength(minute: 1200, start: s, end: e, ramp: 30) == 0, "Before night")
        expect(Schedule.strength(minute: 1260, start: s, end: e, ramp: 30) == 0, "Start boundary")
        expect(close(Schedule.strength(minute: 1275, start: s, end: e, ramp: 30), 0.5), "Evening midpoint")
        expect(Schedule.strength(minute: 1290, start: s, end: e, ramp: 30) == 1, "Evening endpoint")
        expect(Schedule.strength(minute: 0, start: s, end: e, ramp: 30) == 1, "Midnight")
        expect(close(Schedule.strength(minute: 405, start: s, end: e, ramp: 30), 0.5), "Morning midpoint")
        expect(Schedule.strength(minute: 420, start: s, end: e, ramp: 30) == 0, "Morning endpoint")
        expect(Schedule.strength(minute: 40, start: 0, end: 60, ramp: 0) == 1, "No fade")
        expect(Schedule.strength(minute: 40, start: 0, end: 0, ramp: 30) == 0, "Equal times disabled")
        expect(Schedule.strength(minute: 605, start: 600, end: 610, ramp: 30) == 1, "Short period clamps fade")
        expect(Schedule.strength(minute: 720, start: 600, end: 780, ramp: 30) == 1, "Same-day period")
        expect(Schedule.strength(minute: 800, start: 600, end: 780, ramp: 30) == 0, "Same-day outside")
        let neutral = Gains.temperature(6500, brightness: 1, strength: 1)
        expect(neutral == .identity, "6500K identity")
        expect(Gains.temperature(3000, brightness: 0.3, strength: 0) == .identity, "Disabled identity")
        var previousBlue = 0.0
        for k in stride(from: 2700.0, through: 6500.0, by: 50) {
            let g = Gains.temperature(k, brightness: 1, strength: 1)
            expect(g.red == 1 && g.green > 0 && g.green <= 1 && g.blue > 0 && g.blue <= 1, "Safe RGB range \(k)")
            expect(g.blue >= previousBlue, "Monotonic warmth \(k)")
            previousBlue = g.blue
        }
        let dim = Gains.temperature(6500, brightness: 0.3, strength: 1)
        expect(close(dim.red, 0.3) && close(dim.blue, 0.3), "Brightness floor")
        let baseline: [Float] = [0, 0.15, 0.6, 1]
        let expected: [Float] = [0, 0.045, 0.18, 0.3]
        expect(zip(dim.transform(baseline, channel: dim.red), expected).allSatisfy { abs($0 - $1) < 0.000001 }, "Baseline calibration retained")
        var p = Preferences()
        p.kelvin = .nan; p.brightness = -.infinity; p.startMinute = -1; p.endMinute = 1500
        p.sanitize()
        expect(p.kelvin == 4200 && p.brightness == 0.9 && p.startMinute == 1439 && p.endMinute == 60, "Sanitize persisted settings")
        p.enabled = false
        expect(p.strength(at: Date()) == 0, "Off overrides schedule")
        p.enabled = true; p.scheduled = false
        expect(p.strength(at: Date()) == 1, "Manual overrides schedule")
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        expect(restored.kelvin == p.kelvin && restored.enabled == p.enabled, "Settings round trip")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        p.scheduled = true; p.startMinute = s; p.endMinute = e
        let iso = ISO8601DateFormatter()
        expect(p.strength(at: iso.date(from: "2026-11-01T05:30:00Z")!, calendar: calendar) == 1, "DST first 01:30")
        expect(p.strength(at: iso.date(from: "2026-11-01T06:30:00Z")!, calendar: calendar) == 1, "DST repeated 01:30")
        for minute in 0..<1440 {
            let result = Schedule.strength(minute: Double(minute), start: s, end: e, ramp: 30)
            expect(result >= 0 && result <= 1 && result.isFinite, "Full-day bounded \(minute)")
        }
        print("PASS: \(checks) schedule, color, settings, and DST checks")
    }
}
