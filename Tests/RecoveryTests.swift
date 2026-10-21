import Foundation
import CoreGraphics

final class RecoveryDisplay: DisplayAccess {
    let baseline = GammaTable(red: [0, 0.4, 1], green: [0, 0.5, 1], blue: [0, 0.6, 1])
    var tables: [CGDirectDisplayID: GammaTable] = [:]
    var online: [CGDirectDisplayID] = [1]
    var failures = Set<CGDirectDisplayID>()
    var unreadable = false
    var writes = 0
    init() { tables[1] = baseline; tables[2] = baseline }
    func ids() -> [CGDirectDisplayID] { online }
    func read(_ id: CGDirectDisplayID) -> GammaTable? { unreadable ? nil : tables[id] }
    func write(_ table: GammaTable, to id: CGDirectDisplayID, gains: Gains) -> CGError {
        guard online.contains(id), !failures.contains(id) else { return .failure }
        tables[id] = table.transformed(gains); writes += 1; return .success
    }
    func restoreSystem() { for id in online { tables[id] = baseline } }
    func isWarm(_ id: CGDirectDisplayID = 1) -> Bool { (tables[id]?.blue.last ?? 1) < 0.95 }
}

final class FakeRecoveryClock {
    var now = 0.0
    var jobs: [(Double, DispatchWorkItem)] = []
    func schedule(_ delay: TimeInterval, _ item: DispatchWorkItem) { jobs.append((now + delay, item)) }
    func advance(_ delta: TimeInterval) {
        let end = now + delta
        while let i = jobs.indices.filter({ jobs[$0].0 <= end }).min(by: { jobs[$0].0 < jobs[$1].0 }) {
            let job = jobs.remove(at: i); now = job.0
            if !job.1.isCancelled { job.1.perform() }
        }
        now = end
    }
}

@main struct RecoveryTests {
    static func main() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if !value() { fatalError("FAIL: \(name)") }
        }
        let warm = Gains.temperature(4200, brightness: 0.9, strength: 1)
        func makeEngine(_ d: RecoveryDisplay) -> DisplayEngine {
            DisplayEngine(displays: d, recoveryStart: { true }, recoveryStop: {}, animationDuration: 0)
        }

        let d = RecoveryDisplay()
        // A: reproduce the audited late system reset, using the same target.
        let e = makeEngine(d)
        e.set(warm); expect(d.isWarm(), "Initial warmth applies")
        let written = d.writes
        for _ in 0..<5 { e.set(warm) }
        expect(d.writes == written, "Healthy unchanged display is not rewritten")
        d.restoreSystem(); e.set(warm)
        expect(d.isWarm(), "Late system reset heals without changing settings")
        e.restore()
        expect(d.tables[1]!.matches(d.baseline, tolerance: 0), "Drift repair preserves original calibration")

        // B: same target retries after the display becomes available.
        d.online = []; e.set(warm)
        expect(e.lastError != nil, "Transient no-display condition reported")
        d.online = [1]; e.set(warm)
        expect(d.isWarm() && e.lastError == nil, "Display readiness delay recovers on next evaluation")
        e.restore()

        // Preserve a baseline while its tinted display is temporarily absent.
        e.set(warm); d.online = []; e.suspend()
        d.online = [1]; e.set(warm)
        expect(d.tables[1]!.matches(d.baseline.transformed(warm), tolerance: 0), "Resume does not capture or compound tinted baseline")
        e.restore(); expect(d.tables[1]!.matches(d.baseline, tolerance: 0), "Restore exact baseline after unavailable suspend")

        // Failed writes must remain retryable even though the target is cached.
        d.failures = [1]; e.set(warm)
        expect(!d.isWarm() && e.lastError != nil, "Failed write does not masquerade as applied")
        d.failures = []; e.set(warm)
        expect(d.isWarm() && e.lastError == nil, "Identical target retries failed write")
        e.restore()

        // Handle partial multi-screen failure and reconnect without compounding.
        d.online = [1, 2]; d.failures = [2]; e.set(warm)
        expect(d.isWarm(1) && !d.isWarm(2), "Partial display failure is isolated")
        d.failures = []; e.set(warm)
        expect(d.isWarm(1) && d.isWarm(2), "Partial display failure recovers")
        e.suspend(); e.suspend()
        expect(!d.isWarm(1) && !d.isWarm(2), "Suspension restores both screens and is idempotent")
        e.set(warm); d.online = [1]; e.restore()
        expect(!d.isWarm(1) && d.isWarm(2), "Offline restore is deferred")
        d.online = [1, 2]; e.set(.identity)
        expect(!d.isWarm(2), "Deferred original colors restored on reconnect while disabled")

        let unchangedWrites = d.writes
        e.set(.identity, force: true); e.set(.identity)
        expect(d.writes == unchangedWrites, "Repeated recovery cannot warm a disabled display")

        let line3 = GammaTable(red: [0, 0.5, 1], green: [0, 0.5, 1], blue: [0, 0.5, 1])
        let line5 = GammaTable(red: [0, 0.25, 0.5, 0.75, 1], green: [0, 0.25, 0.5, 0.75, 1], blue: [0, 0.25, 0.5, 0.75, 1])
        expect(line3.matches(line5), "Readback tolerates driver resampling")
        let quantized = GammaTable(red: [0, 0.501, 1], green: [0, 0.499, 1], blue: [0, 0.5, 1])
        expect(line3.matches(quantized), "Readback tolerates quantization")
        expect(!line3.matches(line3.transformed(warm)), "Readback detects lost tint")

        var attempts = 0
        let protected = RecoveryDisplay()
        let protectedEngine = DisplayEngine(displays: protected, recoveryStart: { attempts += 1; return attempts > 1 },
                                             recoveryStop: {}, animationDuration: 0)
        protectedEngine.set(warm)
        expect(protected.writes == 0, "Recovery protection failure prevents display changes")
        protectedEngine.set(warm)
        expect(protected.isWarm(), "Same target retries recovery protection startup")
        protectedEngine.restore()

        // The production coordinator and actual engine are driven by a fake
        // clock: no sleeping or changing real displays/session state.
        let clock = FakeRecoveryClock(), screen = RecoveryDisplay()
        let actual = makeEngine(screen)
        var p = Preferences(); p.enabled = true; p.scheduled = false
        var paused = false, evaluations = 0
        var now = ISO8601DateFormatter().date(from: "2026-10-20T22:00:00Z")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let coordinator = DisplayRecovery(suspend: { actual.suspend() }, evaluate: {
            evaluations += 1
            let strength = paused ? 0 : p.strength(at: now, calendar: calendar)
            actual.set(.temperature(p.kelvin, brightness: p.brightness, strength: strength), force: true)
        }, schedule: clock.schedule)

        coordinator.receive(.systemSleep); coordinator.receive(.screenSleep); coordinator.receive(.sessionInactive)
        coordinator.receive(.systemWake); clock.advance(20)
        expect(coordinator.isSuspended && evaluations == 0, "System wake alone cannot override sleeping screen/session")
        coordinator.receive(.screenWake); clock.advance(20)
        expect(coordinator.isSuspended && evaluations == 0, "Screen wake cannot override inactive session")
        coordinator.receive(.sessionActive); clock.advance(0.3)
        expect(!coordinator.isSuspended && screen.isWarm(), "Full resume reapplies warmth")
        screen.restoreSystem(); clock.advance(1.3)
        expect(screen.isWarm(), "Later recovery stage heals a post-unlock system reset")
        paused = true; actual.set(.identity); clock.advance(20)
        expect(!screen.isWarm(), "Pending recovery respects pause")

        paused = false; p.enabled = true
        coordinator.receive(.unlocked); p.enabled = false; actual.set(.identity); clock.advance(20)
        expect(!screen.isWarm(), "Pending recovery respects user disabling app")
        p.enabled = true; p.scheduled = true
        coordinator.receive(.unlocked)
        now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
        clock.advance(20)
        expect(!screen.isWarm(), "Recovery recomputes schedule after night becomes day")

        p.scheduled = false
        coordinator.receive(.unlocked); screen.online = []; clock.advance(0.3)
        expect(!screen.isWarm(), "Unavailable first recovery remains neutral")
        screen.online = [1]; clock.advance(1.3)
        expect(screen.isWarm(), "Later recovery stage retries temporary display unavailability")

        coordinator.receive(.unlocked); coordinator.receive(.screenSleep)
        let before = evaluations; clock.advance(20)
        expect(evaluations == before && !screen.isWarm(), "New screen sleep cancels pending resume jobs")
        coordinator.receive(.unlocked); coordinator.cancel()
        clock.advance(20)
        expect(evaluations == before, "Exit cancels queued jobs")

        let freshClock = FakeRecoveryClock()
        var count = 0
        let bounded = DisplayRecovery(suspend: {}, evaluate: { count += 1 }, schedule: freshClock.schedule)
        bounded.recover(); freshClock.advance(100)
        expect(count == 5, "Recovery stages are bounded, not a permanent retry write loop")
        actual.restore(); e.restore()
        print("PASS: \(checks) lock/wake recovery regression checks; no real display or session changes")
    }
}
