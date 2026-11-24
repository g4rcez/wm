import Foundation
import Testing

@testable import Common

struct UpgradeTests {
    @Test func aCellarPathBecomesTheOptPath() {
        let path = "/opt/homebrew/Cellar/wm/0.4.2/wm.app"
        #expect(stableBundlePath(path, fileExists: { $0 == "/opt/homebrew/opt/wm/wm.app" }) == "/opt/homebrew/opt/wm/wm.app")
    }

    @Test func aCellarPathStaysWhenThereIsNoOptPath() {
        let path = "/opt/homebrew/Cellar/wm/0.4.2/wm.app"
        #expect(stableBundlePath(path, fileExists: { _ in false }) == path)
    }

    @Test func otherPathsStay() {
        #expect(stableBundlePath("/Applications/wm.app", fileExists: { _ in true }) == "/Applications/wm.app")
        #expect(stableBundlePath("/opt/homebrew/opt/wm/wm.app", fileExists: { _ in true }) == "/opt/homebrew/opt/wm/wm.app")
    }

    @Test func theSameBuildNeedsNoRestart() {
        #expect(!needsRestart(daemonVersion: "0.4.3", daemonBundle: "/Applications/wm.app", cliVersion: "0.4.3", cliBundle: "/Applications/wm.app", fileExists: { _ in true }))
    }

    @Test func anotherVersionNeedsARestart() {
        #expect(needsRestart(daemonVersion: "0.4.2", daemonBundle: nil, cliVersion: "0.4.3", cliBundle: nil, fileExists: { _ in true }))
    }

    @Test func aDaemonWithoutBundleIsJudgedByVersion() {
        #expect(!needsRestart(daemonVersion: "0.4.3", daemonBundle: nil, cliVersion: "0.4.3", cliBundle: "/x/wm.app", fileExists: { _ in true }))
    }

    @Test func aDaemonWhoseBundleIsGoneNeedsARestart() {
        #expect(needsRestart(daemonVersion: "0.4.3", daemonBundle: "/gone/wm.app", cliVersion: "0.4.3", cliBundle: "/x/wm.app", fileExists: { _ in false }))
    }

    @Test func aDaemonFromAnotherBundleNeedsARestart() {
        #expect(needsRestart(daemonVersion: "0.4.3", daemonBundle: "/a/wm.app", cliVersion: "0.4.3", cliBundle: "/b/wm.app", fileExists: { _ in true }))
    }
}
