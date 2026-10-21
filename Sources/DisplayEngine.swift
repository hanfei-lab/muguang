import AppKit
import CoreGraphics
import Darwin

struct GammaTable {
    let red: [Float]
    let green: [Float]
    let blue: [Float]
    func transformed(_ gains: Gains) -> GammaTable {
        GammaTable(red: gains.transform(red, channel: gains.red), green: gains.transform(green, channel: gains.green),
                   blue: gains.transform(blue, channel: gains.blue))
    }
    func matches(_ other: GammaTable, tolerance: Float = 2.0 / 255.0) -> Bool {
        func channelMatches(_ a: [Float], _ b: [Float]) -> Bool {
            guard a.count > 1, b.count > 1 else { return false }
            if a.count == b.count {
                return zip(a, b).allSatisfy { $0.isFinite && $1.isFinite && abs($0 - $1) <= tolerance }
            }
            func sample(_ table: [Float], _ t: Float) -> Float {
                let x = t * Float(table.count - 1), i = Int(x), j = min(i + 1, table.count - 1)
                return table[i] + (table[j] - table[i]) * (x - Float(i))
            }
            return (0...32).allSatisfy {
                let t = Float($0) / 32, x = sample(a, t), y = sample(b, t)
                return x.isFinite && y.isFinite && abs(x - y) <= tolerance
            }
        }
        return channelMatches(red, other.red) && channelMatches(green, other.green) && channelMatches(blue, other.blue)
    }
    func write(to id: CGDirectDisplayID, gains: Gains = .identity) -> CGError {
        let r = gains.transform(red, channel: gains.red)
        let g = gains.transform(green, channel: gains.green)
        let b = gains.transform(blue, channel: gains.blue)
        return CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b)
    }
    static func read(_ id: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 1, capacity <= 65536 else { return nil }
        var r = [Float](repeating: 0, count: Int(capacity)), g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count) == .success,
              count > 1, count <= capacity else { return nil }
        let n = Int(count)
        guard (r.prefix(n) + g.prefix(n) + b.prefix(n)).allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              r.prefix(n).max() ?? 0 > 0, g.prefix(n).max() ?? 0 > 0, b.prefix(n).max() ?? 0 > 0 else { return nil }
        return GammaTable(red: Array(r.prefix(n)), green: Array(g.prefix(n)), blue: Array(b.prefix(n)))
    }
}

func activeDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count))).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
}

protocol DisplayAccess {
    func ids() -> [CGDirectDisplayID]
    func read(_ id: CGDirectDisplayID) -> GammaTable?
    func write(_ table: GammaTable, to id: CGDirectDisplayID, gains: Gains) -> CGError
    func restoreSystem()
}
struct SystemDisplayAccess: DisplayAccess {
    func ids() -> [CGDirectDisplayID] { activeDisplayIDs() }
    func read(_ id: CGDirectDisplayID) -> GammaTable? { GammaTable.read(id) }
    func write(_ table: GammaTable, to id: CGDirectDisplayID, gains: Gains) -> CGError { table.write(to: id, gains: gains) }
    func restoreSystem() { CGDisplayRestoreColorSyncSettings() }
}

final class DisplayEngine {
    private let displays: DisplayAccess
    private let recoveryStart: (() -> Bool)?
    private let recoveryStop: (() -> Void)?
    private let animationDuration: TimeInterval
    private var originals: [CGDirectDisplayID: GammaTable] = [:]
    private var applied: [CGDirectDisplayID: Gains] = [:]
    private var suspended = false
    private var protectionActive = false
    private var animation: Timer?
    private var current = Gains.identity
    private var target = Gains.identity
    private var watchdog: Process?
    private var watchdogInput: FileHandle?
    var onStatus: ((String?) -> Void)?
    private(set) var lastError: String?

    init(displays: DisplayAccess = SystemDisplayAccess(), recoveryStart: (() -> Bool)? = nil, recoveryStop: (() -> Void)? = nil,
         animationDuration: TimeInterval = 1.5) {
        self.displays = displays; self.recoveryStart = recoveryStart; self.recoveryStop = recoveryStop
        self.animationDuration = max(0, animationDuration)
    }

    func set(_ gains: Gains, force: Bool = false) {
        let unchanged = gains == target
        suspended = false
        if gains == .identity {
            if !unchanged || !originals.isEmpty { restore() }
            return
        }
        if unchanged && !force {
            if animation != nil { return }
            if !needsReapply(gains) { return }
        }
        target = gains
        animation?.invalidate()
        animation = nil
        captureNewDisplays()
        let online = Set(displays.ids())
        guard originals.keys.contains(where: { online.contains($0) }) else {
            report(online.isEmpty ? "显示器尚未就绪，暮光会自动重试。" : "当前显示器不支持色彩调节。可尝试关闭 HDR 后重试。")
            return
        }
        guard startWatchdog() else { report("恢复保护未能启动，请退出后重新打开暮光。") ; return }
        // Same-target repair must not restart a fade on every retry.
        if unchanged || animationDuration == 0 {
            current = gains; apply(gains, skipMatching: unchanged && !force); return
        }
        let from = current
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / self.animationDuration)
            let eased = t * t * (3 - 2 * t)
            self.current = Gains.mix(from, gains, fraction: eased)
            self.apply(self.current)
            if t >= 1 { timer.invalidate(); self.animation = nil }
        }
        animation = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func needsReapply(_ gains: Gains) -> Bool {
        let ids = displays.ids()
        let hasProtection = recoveryStart != nil ? protectionActive : watchdog?.isRunning == true
        if ids.isEmpty || !hasProtection { return true }
        for id in ids {
            guard let baseline = originals[id], applied[id] == gains,
                  let actual = displays.read(id), actual.matches(baseline.transformed(gains)) else { return true }
        }
        return false
    }

    private func apply(_ gains: Gains, skipMatching: Bool = false) {
        var failures = 0
        let online = Set(displays.ids())
        for (id, table) in originals where online.contains(id) {
            if skipMatching, applied[id] == gains, let actual = displays.read(id), actual.matches(table.transformed(gains)) { continue }
            if displays.write(table, to: id, gains: gains) == .success { applied[id] = gains }
            else { applied.removeValue(forKey: id); failures += 1 }
        }
        if online.isEmpty { report("显示器尚未就绪，暮光会自动重试。") }
        else { report(failures > 0 ? "\(failures) 台显示器未能应用调节，暮光会自动重试。" : captureWarning) }
    }

    private var captureWarning: String?
    private func captureNewDisplays() {
        let ids = displays.ids()
        // Keep snapshots over a transient disconnect or lock/wake transition.
        // Otherwise a reconnect could capture our tinted table as the baseline.
        var skipped = 0
        for id in ids where originals[id] == nil {
            if let table = displays.read(id) { originals[id] = table } else { skipped += 1 }
        }
        captureWarning = skipped > 0 ? "\(skipped) 台显示器不支持调节，其余显示器已应用。" : nil
    }

    // Keep existing baselines: reading an already tinted screen would compound tint.
    func refresh() { set(target, force: true) }

    func restore() {
        restore(keepingBaselines: false)
    }

    func suspend() {
        guard !suspended else { return }
        restore(keepingBaselines: true)
        suspended = true
    }

    private func restore(keepingBaselines: Bool) {
        animation?.invalidate(); animation = nil
        let connected = Set(displays.ids())
        var failed = false
        for (id, table) in originals where connected.contains(id) {
            if displays.write(table, to: id, gains: .identity) != .success { failed = true }
        }
        if failed { displays.restoreSystem() }
        if !keepingBaselines {
            // Retain offline snapshots until they can actually be restored.
            originals = originals.filter { !connected.contains($0.key) }
        }
        applied.removeAll(); suspended = false
        target = .identity; current = .identity
        stopWatchdog()
        report(nil)
    }

    private func report(_ message: String?) {
        guard lastError != message else { return }
        lastError = message; onStatus?(message)
    }

    private func startWatchdog() -> Bool {
        if let custom = recoveryStart {
            if protectionActive { return true }
            protectionActive = custom(); return protectionActive
        }
        if watchdog?.isRunning == true { return true }
        try? watchdogInput?.close(); watchdogInput = nil
        let child = Process(), pipe = Pipe()
        child.executableURL = Bundle.main.executableURL
        child.arguments = ["--watchdog"]
        child.standardInput = pipe
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { return false }
        // Parent must not retain a duplicate reader or a write descriptor in children.
        pipe.fileHandleForReading.closeFile()
        watchdog = child; watchdogInput = pipe.fileHandleForWriting; protectionActive = true
        return true
    }
    private func stopWatchdog() {
        if let custom = recoveryStop {
            if protectionActive { custom() }; protectionActive = false; return
        }
        if let handle = watchdogInput {
            // FileHandle.write(contentsOf:) requires 10.15.4. POSIX writes also
            // let us handle a dead watchdog without Objective-C exceptions.
            Data("clean".utf8).withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(handle.fileDescriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    if count <= 0 { break }
                    offset += count
                }
            }
            try? handle.close()
        }
        watchdogInput = nil; watchdog = nil; protectionActive = false
    }
}
