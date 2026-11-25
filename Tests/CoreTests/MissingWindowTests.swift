import Testing
@testable import Core

@Suite("MissingWindow")
struct MissingWindowTests {
    @Test func aWindowOnAnotherSpaceIsKept() {
        #expect(!shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .elsewhere, goneFor: 0))
    }

    @Test func aWindowOnAnotherSpaceIsKeptWhateverTheOtherAnswersAre() {
        #expect(!shouldForgetMissingWindow(appUnreadable: false, inSystemList: false, place: .elsewhere, goneFor: 0))
        #expect(!shouldForgetMissingWindow(appUnreadable: true, inSystemList: true, place: .elsewhere, goneFor: 0))
    }

    @Test func aClosedWindowIsForgotten() {
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: false, place: .gone, goneFor: 0))
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .gone, goneFor: spaceTransitionGrace))
    }

    @Test func aWindowOfAnAppThatCouldNotBeReadIsKeptWhileTheSystemStillHasIt() {
        #expect(!shouldForgetMissingWindow(appUnreadable: true, inSystemList: true, place: .here, goneFor: 0))
        #expect(!shouldForgetMissingWindow(appUnreadable: true, inSystemList: true, place: .unknown, goneFor: 0))
    }

    @Test func aWindowOfAnAppThatCouldNotBeReadIsForgottenWhenTheSystemLostIt() {
        #expect(shouldForgetMissingWindow(appUnreadable: true, inSystemList: false, place: .gone, goneFor: 0))
    }

    @Test func aHiddenWindowOnTheActiveSpaceIsForgottenAsBefore() {
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .here, goneFor: 0))
    }

    @Test func withoutThePrivateFunctionsTheOldRuleHolds() {
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .unknown, goneFor: 0))
    }

    @Test func aWindowOnItsWayBetweenSpacesIsKept() {
        #expect(!shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .gone, goneFor: 0))
        #expect(!shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .gone, goneFor: spaceTransitionGrace - 0.1))
    }

    @Test func aWindowThatStaysOnNoSpaceIsForgotten() {
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .gone, goneFor: spaceTransitionGrace))
    }

    @Test func aWindowThatTheSystemLostGetsNoGrace() {
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: false, place: .gone, goneFor: 0))
    }
}
