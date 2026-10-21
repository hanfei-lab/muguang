import AppKit
import CoreGraphics
import Darwin

let arguments = CommandLine.arguments
if arguments.contains("--watchdog") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let shouldRestore = String(data: data, encoding: .utf8) != "clean"
    if arguments.contains("--probe") {
        // Test the real EOF/clean-exit protocol without changing a display.
        print(shouldRestore ? "restore-required" : "clean-exit")
    } else if shouldRestore { CGDisplayRestoreColorSyncSettings() }
    exit(0)
}
if arguments.contains("--restore") {
    CGDisplayRestoreColorSyncSettings()
    print("已恢复系统 ColorSync 色彩配置。")
    exit(0)
}
if arguments.contains("--diagnostics") {
    let ids = activeDisplayIDs()
    print("暮光 0.2.2 · \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("在线显示器：\(ids.count)（此检查不修改屏幕）")
    for id in ids {
        print("显示器 \(id): \(CGDisplayPixelsWide(id))×\(CGDisplayPixelsHigh(id)), gamma capacity=\(CGDisplayGammaTableCapacity(id)), readable=\(GammaTable.read(id) != nil)")
    }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var preferences = Preferences()
    var pauseUntil: Date?
    var message: String?
    var isPaused: Bool { (pauseUntil ?? .distantPast) > Date() }
    private let loginController = LoginController()
    var loginEnabled: Bool { loginController.state == .enabled }
    var loginRequiresApproval: Bool { loginController.state == .requiresApproval }
    private let engine = DisplayEngine()
    private let panel = PanelController()
    private let popover = NSPopover()
    private var status: NSStatusItem!
    private var scheduler: Timer?
    private lazy var recovery = DisplayRecovery(
        suspend: { [weak self] in self?.engine.suspend(); self?.panel.refresh() },
        evaluate: { [weak self] in self?.evaluate(force: true) })
    private let dryRun = arguments.contains("--smoke-test") || arguments.contains("--preview")
    private let preferenceKey = "MuguangPreferences.v1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.accessory)
        if !dryRun, let data = UserDefaults.standard.data(forKey: preferenceKey),
           let p = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = p }
        preferences.sanitize()
        panel.owner = self
        _ = panel.view
        if dryRun {
            runSmokeTest()
            return
        }
        loginController.refresh()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = AppImages.sun(size: 18, template: true)
            button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient; popover.contentViewController = panel
        popover.contentSize = NSSize(width: 376, height: panel.view.fittingSize.height)
        engine.onStatus = { [weak self] error in
            guard let self = self else { return }
            self.message = error; self.panel.refresh()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensWillSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        // Best-effort macOS unlock signal; public screen/session notifications
        // and periodic readback remain independent fallbacks.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, suspensionBehavior: .deliverImmediately)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSNotification.Name.NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.evaluate() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common); scheduler = timer
        evaluate()
        if !UserDefaults.standard.bool(forKey: "HasOpenedMuguang") {
            UserDefaults.standard.set(true, forKey: "HasOpenedMuguang")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showPanel() }
        }
    }

    func update(_ mutation: (inout Preferences) -> Void) {
        mutation(&preferences); preferences.sanitize()
        if !preferences.enabled { pauseUntil = nil }
        message = nil
        if !dryRun, let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: preferenceKey)
        }
        evaluate()
    }
    func togglePause() {
        pauseUntil = isPaused ? nil : Date().addingTimeInterval(15 * 60)
        message = nil; evaluate()
    }
    func setLogin(_ wanted: Bool) {
        guard !dryRun else { return }
        do {
            try loginController.setEnabled(wanted)
            message = nil
        } catch { message = "登录启动设置未完成：\(error.localizedDescription)" }
        panel.refresh()
    }
    private func evaluate(force: Bool = false) {
        if let deadline = pauseUntil, deadline <= Date() { pauseUntil = nil }
        if preferences.scheduled && preferences.startMinute == preferences.endMinute {
            message = "开始和结束时间相同，请设置不同的时间。"
        } else if message?.hasPrefix("开始和结束") == true { message = nil }
        let strength = isPaused ? 0 : preferences.strength(at: Date())
        if !dryRun {
            if recovery.isSuspended { engine.suspend() }
            else { engine.set(.temperature(preferences.kelvin, brightness: preferences.brightness, strength: strength), force: force) }
            status.button?.toolTip = !preferences.enabled ? "暮光 · 已关闭" : isPaused ? "暮光 · 已暂停" : "暮光 · 点击调节"
        }
        if preferences.scheduled && preferences.startMinute == preferences.endMinute {
            message = "开始和结束时间相同，请设置不同的时间。"
        }
        panel.refresh()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for (title, action) in [("打开暮光", #selector(showPanel)), (isPaused ? "继续调节" : "暂停 15 分钟", #selector(menuPause)), ("恢复原色", #selector(menuRestore)), ("退出暮光", #selector(menuQuit))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
                if action == #selector(menuPause) { item.isEnabled = preferences.enabled }
                menu.addItem(item)
            }
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }
    @objc func showPanel() {
        guard let button = status?.button else { return }
        loginController.refresh()
        evaluate()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func menuPause() { togglePause() }
    @objc private func menuRestore() { update { $0.enabled = false } }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    private func onMain(_ action: @escaping (AppDelegate) -> Void) {
        if Thread.isMainThread { action(self) }
        else { DispatchQueue.main.async { [weak self] in if let self = self { action(self) } } }
    }
    @objc private func systemWillSleep() { onMain { $0.recovery.receive(.systemSleep) } }
    @objc private func systemDidWake() { onMain { $0.recovery.receive(.systemWake) } }
    @objc private func screensWillSleep() { onMain { $0.recovery.receive(.screenSleep) } }
    @objc private func screensDidWake() { onMain { $0.recovery.receive(.screenWake) } }
    @objc private func sessionResigned() { onMain { $0.recovery.receive(.sessionInactive) } }
    @objc private func sessionBecameActive() { onMain { $0.recovery.receive(.sessionActive) } }
    @objc private func screenUnlocked() {
        // Distributed notifications can describe another user's session.
        onMain { app in
            guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
                  session[kCGSessionOnConsoleKey as String] as? Bool == true else { return }
            app.recovery.receive(.unlocked)
        }
    }
    @objc private func displayChanged() { onMain { $0.recovery.recover() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        recovery.cancel(); scheduler?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        if !dryRun { engine.restore() }
    }

    private func runSmokeTest() {
        // Exercise actual controls without saving preferences or touching gamma tables.
        preferences = Preferences()
        panel.refresh()
        panel.enabled.state = .on
        _ = panel.enabled.sendAction(panel.enabled.action, to: panel.enabled.target)
        guard preferences.enabled else { fatalError("Enable control failed") }
        panel.temperature.doubleValue = 3500
        _ = panel.temperature.sendAction(panel.temperature.action, to: panel.temperature.target)
        guard preferences.kelvin == 3500 else { fatalError("Temperature control failed") }
        panel.brightness.doubleValue = 80
        _ = panel.brightness.sendAction(panel.brightness.action, to: panel.brightness.target)
        guard preferences.brightness == 0.8 else { fatalError("Brightness control failed") }
        panel.pause.performClick(nil)
        guard isPaused else { fatalError("Pause control failed") }
        panel.pause.performClick(nil)
        guard !isPaused else { fatalError("Resume control failed") }
        preferences = Preferences(); preferences.enabled = true
        panel.refresh()
        panel.view.setFrameSize(NSSize(width: 376, height: panel.view.fittingSize.height))
        panel.view.layoutSubtreeIfNeeded()
        if let index = arguments.firstIndex(of: "--preview"), arguments.count > index + 1 {
            let url = URL(fileURLWithPath: arguments[index + 1])
            guard let rep = panel.view.bitmapImageRepForCachingDisplay(in: panel.view.bounds) else { fatalError("Render failed") }
            panel.view.cacheDisplay(in: panel.view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG failed") }
            do { try data.write(to: url) } catch { fatalError("\(error)") }
            print("Preview saved: \(url.path)")
        }
        print("UI smoke test passed: enable, temperature, brightness, pause, resume; no display writes.")
        exit(0)
    }
}

if !arguments.contains("--smoke-test") && !arguments.contains("--preview"),
   let identifier = Bundle.main.bundleIdentifier,
   let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != getpid() }) {
    other.activate(options: [.activateIgnoringOtherApps]); exit(0)
}
guard !activeDisplayIDs().isEmpty else {
    FileHandle.standardError.write(Data("当前会话无法访问桌面显示器，请在已登录的 macOS 桌面中打开暮光。界面自检需要桌面会话；--diagnostics 可在此环境运行。\n".utf8))
    exit(69)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
if arguments.contains("--smoke-test") || arguments.contains("--preview") {
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
} else {
    app.run()
}
