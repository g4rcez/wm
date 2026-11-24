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

    @Test func secureInputIsAWarningThatNamesTheApp() {
        var facts = healthy
        facts.secureInput = "Terminal"
        let checks = daemonChecks(facts)

        let secure = checks.first { $0.name == "secure input" }
        #expect(secure?.status == .warn)
        #expect(secure?.detail.contains("Terminal") == true)
        #expect(secure?.hint?.contains("Secure Keyboard Entry") == true)
        #expect(daemonChecks(healthy).contains { $0.name == "secure input" } == false)
    }

    @Test func factsWithNoSecureInputFieldStillDecode() throws {
        let json = #"{"accessibility":true,"keyTap":true,"screenRecording":true,"loginItemWanted":false,"loginItemEnabled":false,"isAppBundle":true,"onboarded":true}"#
        let facts = try JSONDecoder().decode(DoctorFacts.self, from: Data(json.utf8))
        #expect(facts.secureInput == nil)
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

struct ShortcutsCheckTests {
    @Test func noFileIsSkipped() {
        let check = shortcutsCheck(fileExists: false, imported: false, count: 0, problem: nil, overrides: [])

        #expect(check == DoctorCheck("shortcuts", .skip, "no shortcuts.toml: init.lua is the only source of binds"))
    }

    @Test func aBrokenFileFailsWithTheLine() {
        let check = shortcutsCheck(fileExists: true, imported: true, count: 0, problem: "shortcuts.toml line 3: bad", overrides: [])

        #expect(check.status == .fail)
        #expect(check.detail == "shortcuts.toml line 3: bad")
    }

    @Test func aFileThatInitLuaDoesNotLoadWarnsAndNamesTheLine() {
        let check = shortcutsCheck(fileExists: true, imported: false, count: 4, problem: nil, overrides: [])

        #expect(check == DoctorCheck(
            "shortcuts", .warn, "shortcuts.toml has 4 shortcuts, but init.lua does not call wm.shortcuts(): none is bound",
            hint: "add `wm.shortcuts()` to init.lua"))
    }

    @Test func conflictsAreListed() {
        let check = shortcutsCheck(
            fileExists: true, imported: true, count: 4, problem: nil,
            overrides: ["main: alt-h (init.lua replaces shortcuts.toml: focus left)", "main: alt-l (init.lua replaces shortcuts.toml: focus right)"])

        #expect(check.status == .warn)
        #expect(check.detail == "2 in conflict: main: alt-h (init.lua replaces shortcuts.toml: focus left); main: alt-l (init.lua replaces shortcuts.toml: focus right)")
    }

    @Test func aLoadedFileWithoutConflictsIsOk() {
        #expect(shortcutsCheck(fileExists: true, imported: true, count: 4, problem: nil, overrides: []) == DoctorCheck("shortcuts", .ok, "4 shortcuts"))
    }

    @Test func aWarningDoesNotFailTheExitCode() {
        let check = shortcutsCheck(fileExists: true, imported: false, count: 1, problem: nil, overrides: [])

        #expect(doctorExitCode([check]) == 0)
    }
}

struct NativeDoctorTests {
    private let good = NativeFacts(canList: true, canMoveWindows: true, rearrangesSpaces: false, separateSpaces: true, desktops: 4, missing: [])

    @Test func healthyDesktopsAreAllOk() {
        #expect(nativeChecks(good).allSatisfy { $0.status == .ok })
    }

    @Test func missingDesktopsAndRearrangingAreWarnings() {
        var facts = good
        facts.missing = ["5", "web"]
        facts.rearrangesSpaces = true
        let checks = nativeChecks(facts)
        #expect(checks.first { $0.name == "desktops needed" }?.detail.contains("5, web") == true)
        #expect(checks.first { $0.name == "desktop order" }?.status == .warn)
    }

    @Test func missingDesktopsAreMadeWhenWmCanMakeThem() {
        var facts = good
        facts.missing = ["5"]
        facts.canCreate = true
        let check = nativeChecks(facts).first { $0.name == "desktops needed" }
        #expect(check?.status == .ok)
        #expect(check?.detail.contains("5") == true)
    }

    @Test func noListingIsAFailure() {
        var facts = good
        facts.canList = false
        #expect(nativeChecks(facts).first { $0.name == "desktops" }?.status == .fail)
    }
}
