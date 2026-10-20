import Foundation
import ServiceManagement

final class LoginController {
    enum State { case disabled, enabled, requiresApproval }
    private(set) var state = State.disabled

    func refresh() {
        if #available(macOS 13, *) {
            switch SMAppService.mainApp.status {
            case .enabled: state = .enabled
            case .requiresApproval: state = .requiresApproval
            default: state = .disabled
            }
        } else {
            let jobs = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: Any]] ?? []
            state = LoginSupport.legacyEnabled(jobs: jobs) ? .enabled : .disabled
        }
    }

    func setEnabled(_ wanted: Bool) throws {
        if #available(macOS 13, *) {
            if wanted { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } else {
            let helper = LoginSupport.helperURL(in: Bundle.main.bundleURL)
            guard FileManager.default.fileExists(atPath: helper.appendingPathComponent("Contents/MacOS/MuguangLoginHelper").path) else {
                throw NSError(domain: "MuguangLogin", code: 1, userInfo: [NSLocalizedDescriptionKey: "登录启动组件缺失，请重新安装完整的暮光应用。"])
            }
            guard SMLoginItemSetEnabled(LoginSupport.helperIdentifier as CFString, wanted) else {
                throw NSError(domain: "MuguangLogin", code: 2, userInfo: [NSLocalizedDescriptionKey: "系统未能更改登录启动。请将暮光放入「应用程序」后重试。"])
            }
            // Reflect the successful request immediately; re-query when opening the panel.
            state = wanted ? .enabled : .disabled
        }
    }
}
