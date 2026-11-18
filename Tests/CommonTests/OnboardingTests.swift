import Foundation
import Testing

@testable import Common

struct OnboardingTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wm-onboarding-\(UUID().uuidString)")

    @Test func theMarkerLivesInTheStateFolder() {
        let home = URL(fileURLWithPath: "/Users/someone")

        #expect(Onboarding.markerURL(environment: [:], home: home).path == "/Users/someone/.local/state/wm/onboarded")
        #expect(Onboarding.markerURL(environment: ["XDG_STATE_HOME": "/data/state"], home: home).path == "/data/state/wm/onboarded")
        #expect(Onboarding.markerURL(environment: ["XDG_STATE_HOME": ""], home: home).path == "/Users/someone/.local/state/wm/onboarded")
    }

    @Test func theSetupIsPendingUntilTheMarkerExists() throws {
        let marker = folder.appendingPathComponent("wm/onboarded")
        #expect(!Onboarding.isDone(marker: marker))

        try Onboarding.markDone(marker: marker)

        #expect(Onboarding.isDone(marker: marker))
        #expect(try String(contentsOf: marker, encoding: .utf8) == "\(wmVersion)\n")
    }

    @Test func markingTwiceIsFine() throws {
        let marker = folder.appendingPathComponent("wm/onboarded")

        try Onboarding.markDone(marker: marker)
        try Onboarding.markDone(marker: marker)

        #expect(Onboarding.isDone(marker: marker))
    }
}
