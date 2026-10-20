import Foundation
import CoreGraphics

final class FakeDisplays: DisplayAccess {
    var connected: [CGDirectDisplayID] = [1, 2]
    var tables: [CGDirectDisplayID: GammaTable] = [
        1: GammaTable(red: [0, 0.3, 1], green: [0, 0.4, 1], blue: [0, 0.5, 1]),
        2: GammaTable(red: [0, 0.25, 0.9], green: [0, 0.35, 0.9], blue: [0, 0.45, 0.9])
    ]
    var reads: [CGDirectDisplayID: Int] = [:]
    var writes: [(CGDirectDisplayID, Gains)] = []
    var failures = Set<CGDirectDisplayID>()
    var systemRestores = 0
    func ids() -> [CGDirectDisplayID] { connected }
    func read(_ id: CGDirectDisplayID) -> GammaTable? { reads[id, default: 0] += 1; return tables[id] }
    func write(_ table: GammaTable, to id: CGDirectDisplayID, gains: Gains) -> CGError {
        writes.append((id, gains))
        if failures.contains(id) { return .failure }
        tables[id] = GammaTable(red: gains.transform(table.red, channel: gains.red),
                                green: gains.transform(table.green, channel: gains.green),
                                blue: gains.transform(table.blue, channel: gains.blue))
        return .success
    }
    func restoreSystem() { systemRestores += 1 }
}

@main struct DisplayTests {
    static func main() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if !value() { fatalError("FAIL: \(name)") }
        }
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(1.7)) }
        let displays = FakeDisplays()
        let initial = displays.tables
        var protections = 0
        let engine = DisplayEngine(displays: displays, recoveryStart: { protections += 1; return true }, recoveryStop: { protections -= 1 })
        let warm = Gains.temperature(3000, brightness: 0.6, strength: 1)
        engine.set(warm); settle()
        expect(displays.tables[1]!.blue.last! < 0.6, "Warmth applied")
        expect(displays.tables[2]!.red.last! < 0.9, "Second display dimmed")
        let readCount = displays.reads
        engine.set(.temperature(4200, brightness: 0.8, strength: 1)); settle()
        expect(displays.reads == readCount, "No tinted baseline recapture")
        engine.restore()
        expect(displays.tables[1]!.red == initial[1]!.red && displays.tables[1]!.blue == initial[1]!.blue, "Calibration 1 restored exactly")
        expect(displays.tables[2]!.green == initial[2]!.green, "Calibration 2 restored exactly")
        let count = displays.writes.count
        engine.set(.identity)
        expect(displays.writes.count == count, "Neutral state does not rewrite displays")

        engine.set(warm); settle()
        displays.connected = [1]
        let beforeRestore = displays.writes.count
        engine.restore()
        expect(displays.writes.dropFirst(beforeRestore).allSatisfy { $0.0 == 1 }, "Unplugged display skipped during restore")
        displays.connected = [1, 2]
        displays.tables = initial
        engine.set(warm); settle()
        displays.failures = [1]
        engine.restore()
        expect(displays.systemRestores == 1, "Restore failure falls back to system profile")
        displays.failures = []
        displays.connected = []
        engine.set(warm)
        expect(engine.lastError != nil, "Unsupported display reported")
        engine.restore()
        let blocked = FakeDisplays()
        let protectedEngine = DisplayEngine(displays: blocked, recoveryStart: { false }, recoveryStop: {})
        protectedEngine.set(warm); settle()
        expect(blocked.writes.isEmpty && protectedEngine.lastError != nil, "No changes if recovery protection fails")
        print("PASS: \(checks) display lifecycle checks using simulated displays; no hardware changes")
    }
}
