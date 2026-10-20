import Foundation

@main struct LoginSupportTests {
    static func main() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if !value() { fatalError("FAIL: \(name)") }
        }
        for path in ["/Applications/暮光.app", "/Users/person/Applications/My Warm Light.app", "/Volumes/软件/暮光.app"] {
            let main = URL(fileURLWithPath: path, isDirectory: true)
            let helper = LoginSupport.helperURL(in: main)
            expect(LoginSupport.mainURL(fromHelper: helper) == main, "Find containing app after rename or move")
        }
        expect(LoginSupport.mainURL(fromHelper: URL(fileURLWithPath: "/tmp/Helper.app")) == nil, "Reject standalone helper")
        expect(LoginSupport.mainURL(fromHelper: URL(fileURLWithPath: "/Applications/Test.app/Wrong/Library/LoginItems/Helper.app")) == nil, "Reject wrong bundle layout")
        expect(!LoginSupport.legacyEnabled(jobs: []), "Empty state disabled")
        expect(!LoginSupport.legacyEnabled(jobs: [["Label": "another.helper", "OnDemand": true]]), "Ignore unrelated jobs")
        expect(!LoginSupport.legacyEnabled(jobs: [["Label": LoginSupport.helperIdentifier, "OnDemand": false]]), "Disabled job")
        expect(!LoginSupport.legacyEnabled(jobs: [["Label": LoginSupport.helperIdentifier]]), "Do not infer enabled without state")
        expect(LoginSupport.legacyEnabled(jobs: [["Label": LoginSupport.helperIdentifier, "OnDemand": true]]), "Enabled job")
        expect(LoginSupport.legacyEnabled(jobs: [["Label": "other"], ["Label": LoginSupport.helperIdentifier, "OnDemand": true]]), "Find job among other services")
        print("PASS: \(checks) legacy login-state and helper-location checks; no login changes")
    }
}
