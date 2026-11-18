import Foundation
import Testing

@testable import Common

struct DoctorTests {
    private let healthy = DoctorFacts(
        accessibility: true, keyTap: true, screenRecording: true, loginItemWanted: true, loginItemEnabled: true, isAppBundle: true,
        onboarded: true)

    @Test func aHealthyDaemonHasOnlyOkChecks() {
        let checks = daemonChecks(healthy)

        #expect(checks.map(\.name) == ["setup", "accessibility", "keys", "screen recording", "login item"])
        #expect(checks.allSatisfy { $0.status == .ok })
        #expect(doctorExitCode(checks) == 0)
    }

    @Test func missingAccessibilityFailsAndSaysWhereToGrantIt() {
        var facts = healthy
        facts.accessibility = false
        facts.keyTap = false

        let checks = daemonChecks(facts)

        #expect(checks[1] == DoctorCheck(
            "accessibility", .fail, "not granted: wm cannot move windows or read keys",
            hint: "turn wm on in System Settings > Privacy & Security > Accessibility"))
        #expect(checks[2].status == .fail)
        #expect(checks[2].hint == "grant Accessibility first")
        #expect(doctorExitCode(checks) == 1)
    }

    @Test func aKeyTapThatDoesNotRunWithAccessibilityAsksForARestart() {
        var facts = healthy
        facts.keyTap = false

        #expect(daemonChecks(facts)[2].hint == "run `wm daemon stop`, then `wm daemon start`")
    }

    @Test func screenRecordingIsOnlyAWarning() {
        var facts = healthy
        facts.screenRecording = false

        let checks = daemonChecks(facts)

        #expect(checks[3].status == .warn)
        #expect(doctorExitCode(checks) == 0)
    }

    @Test func theLoginItemFollowsTheSetting() {
        var wantedButOff = healthy
        wantedButOff.loginItemEnabled = false
        var offButEnabled = healthy
        offButEnabled.loginItemWanted = false
        var offAndOff = healthy
        offAndOff.loginItemWanted = false
        offAndOff.loginItemEnabled = false
        var notABundle = healthy
        notABundle.isAppBundle = false

        #expect(daemonChecks(wantedButOff)[4].detail == "start_at_login is on, but wm is not a login item")
        #expect(daemonChecks(offButEnabled)[4].detail == "wm is a login item, but start_at_login is off")
        #expect(daemonChecks(offAndOff)[4] == DoctorCheck("login item", .ok, "off (start_at_login is not set)"))
        #expect(daemonChecks(notABundle)[4].status == .skip)
    }

    @Test func aSetupThatIsNotFinishedIsAWarningWithAHint() {
        var facts = healthy
        facts.onboarded = false

        let checks = daemonChecks(facts)

        #expect(checks[0] == DoctorCheck(
            "setup", .warn, "not finished: wm moves no window yet",
            hint: "choose Setup… in the wm menu bar menu, then press Start"))
        #expect(doctorExitCode(checks) == 0)
    }

    @Test func theTextShowsAHintUnderACheckThatIsNotOk() {
        let text = renderDoctor([
            DoctorCheck("config", .ok, "/c/init.lua (3 binds)", hint: "ignored"),
            DoctorCheck("daemon", .fail, "wm does not run", hint: "run `wm daemon start`"),
        ])

        #expect(text == """
        ok    config  /c/init.lua (3 binds)
        fail  daemon  wm does not run
                      hint: run `wm daemon start`

        """)
    }

    @Test func theFactsSurviveTheJSONThatTheDaemonSends() throws {
        let data = try JSONEncoder().encode(healthy)

        #expect(try JSONDecoder().decode(DoctorFacts.self, from: data) == healthy)
    }
}
