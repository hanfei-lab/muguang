import Foundation

enum LoginSupport {
    static let mainIdentifier = "dev.muguang.mac"
    static let helperIdentifier = "dev.muguang.mac.LoginHelper"

    static func helperURL(in mainURL: URL) -> URL {
        mainURL.appendingPathComponent("Contents/Library/LoginItems/MuguangLoginHelper.app", isDirectory: true)
    }

    static func mainURL(fromHelper helperURL: URL) -> URL? {
        let loginItems = helperURL.deletingLastPathComponent()
        let library = loginItems.deletingLastPathComponent()
        let contents = library.deletingLastPathComponent()
        let main = contents.deletingLastPathComponent()
        guard helperURL.pathExtension == "app", loginItems.lastPathComponent == "LoginItems",
              library.lastPathComponent == "Library", contents.lastPathComponent == "Contents",
              main.pathExtension == "app" else { return nil }
        return main
    }

    static func legacyEnabled(jobs: [[String: Any]]) -> Bool {
        // Apple's legacy launchd job dictionary exposes enabled login items as OnDemand jobs.
        jobs.contains { ($0["Label"] as? String) == helperIdentifier && ($0["OnDemand"] as? Bool) == true }
    }
}
