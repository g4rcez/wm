import Common
import Testing

struct DoctorFixTests {
    private let healthy = DoctorFacts(
        accessibility: true, keyTap: true, screenRecording: true, loginItemWanted: true, loginItemEnabled: true, isAppBundle: true,
        onboarded: true)

    private func fixes(_ change: (inout DoctorFacts) -> Void, configLoads: Bool = true) -> [DoctorFix] {
        var facts = healthy
        change(&facts)
        return doctorFixes(DoctorState(daemon: .answers(facts), configLoads: configLoads))
    }

    @Test func aHealthyWmNeedsNoFix() {
        #expect(doctorFixes(DoctorState(daemon: .answers(healthy))) == [])
    }

    @Test func aDaemonThatDoesNotRunIsStarted() {
        #expect(doctorFixes(DoctorState(daemon: .down)) == [.startDaemon])
    }

    @Test func anotherBuildOrASilentDaemonIsReplaced() {
        #expect(doctorFixes(DoctorState(daemon: .stale)) == [.replaceDaemon])
        #expect(doctorFixes(DoctorState(daemon: .silent)) == [.replaceDaemon])
    }

    @Test func missingAccessibilityResetsItsEntry() {
        #expect(fixes { $0.accessibility = false; $0.keyTap = false } == [.resetPermissions(screenRecording: false)])
    }

    @Test func screenRecordingIsResetOnlyWhenItIsNotGrantedEither() {
        #expect(fixes { $0.accessibility = false; $0.keyTap = false; $0.screenRecording = false } == [.resetPermissions(screenRecording: true)])
        // Screen Recording alone is optional: the user may not want it.
        #expect(fixes { $0.screenRecording = false } == [])
    }

    @Test func aGrantedPermissionIsNeverReset() {
        let all = fixes { $0.keyTap = false; $0.loginItemEnabled = false }
        #expect(all == [.restartForKeys, .reloadForLoginItem])
    }

    @Test func nothingAboutPermissionsBeforeTheSetupIsDone() {
        #expect(fixes { $0.onboarded = false; $0.accessibility = false; $0.keyTap = false } == [])
    }

    @Test func theLoginItemWaitsForAConfigThatLoads() {
        #expect(fixes({ $0.loginItemEnabled = false }, configLoads: false) == [])
        #expect(fixes { $0.loginItemEnabled = false; $0.isAppBundle = false } == [])
    }

    @Test func oldDiskImagesAreEjectedBeforeWmStarts() {
        let state = DoctorState(daemon: .down, oldDiskImages: ["/Volumes/wm 0.2.0"])
        #expect(doctorFixes(state) == [.ejectDiskImage("/Volumes/wm 0.2.0"), .startDaemon])
    }

    @Test func theSameFixKeepsItsNameWhenItsDetailsChange() {
        #expect(DoctorFix.resetPermissions(screenRecording: true).id == DoctorFix.resetPermissions(screenRecording: false).id)
        #expect(DoctorFix.ejectDiskImage("/Volumes/a").id != DoctorFix.ejectDiskImage("/Volumes/b").id)
    }
}
