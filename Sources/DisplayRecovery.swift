import Foundation

/// Independent flags prevent a screen-wake event from overriding system sleep
/// or a switched-out user session. Delayed callbacks never cache user settings.
final class DisplayRecovery {
    enum Event { case systemSleep, systemWake, screenSleep, screenWake, sessionInactive, sessionActive, unlocked }
    private var systemSleeping = false
    private var screenSleeping = false
    private var sessionInactive = false
    var isSuspended: Bool { systemSleeping || screenSleeping || sessionInactive }
    private var pending: [DispatchWorkItem] = []
    private let suspend: () -> Void
    private let evaluate: () -> Void
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void

    init(suspend: @escaping () -> Void, evaluate: @escaping () -> Void,
         schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = {
             DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
         }) {
        self.suspend = suspend; self.evaluate = evaluate; self.schedule = schedule
    }

    func receive(_ event: Event) {
        switch event {
        case .systemSleep: systemSleeping = true
        case .systemWake: systemSleeping = false
        case .screenSleep: screenSleeping = true
        case .screenWake: screenSleeping = false
        case .sessionInactive: sessionInactive = true
        case .sessionActive: sessionInactive = false
        case .unlocked:
            // Only sent by the app after verifying its session is on-console.
            systemSleeping = false; screenSleeping = false; sessionInactive = false
        }
        cancel()
        if isSuspended { suspend() } else { recover() }
    }

    func recover() {
        cancel()
        guard !isSuspended else { return }
        // Cover delayed display availability and late ColorSync resets, without
        // a permanent high-frequency write loop. Ordinary polling checks drift.
        for delay in [0.2, 1.5, 4.0, 8.0, 15.0] {
            let item = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isSuspended else { return }
                self.evaluate()
            }
            pending.append(item); schedule(delay, item)
        }
    }

    func cancel() { pending.forEach { $0.cancel() }; pending.removeAll() }
    deinit { cancel() }
}
