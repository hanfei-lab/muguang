import AppKit
import Darwin

guard let mainURL = LoginSupport.mainURL(fromHelper: Bundle.main.bundleURL),
      Bundle(url: mainURL)?.bundleIdentifier == LoginSupport.mainIdentifier else { exit(1) }
if !NSRunningApplication.runningApplications(withBundleIdentifier: LoginSupport.mainIdentifier).isEmpty { exit(0) }
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false
NSWorkspace.shared.openApplication(at: mainURL, configuration: configuration) { app, error in
    exit(app != nil && error == nil ? 0 : 1)
}
// Keep only the launch completion alive. The helper is not a second resident app.
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(1) }
RunLoop.main.run()
