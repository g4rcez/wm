import Testing
@testable import Core

@Suite("MissingWindow")
struct MissingWindowTests {
    @Test func aWindowOnAnotherSpaceIsKept() {
        #expect(!shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .elsewhere))
    }

    @Test func aWindowOnAnotherSpaceIsKeptWhateverTheOtherAnswersAre() {
        #expect(!shouldForgetMissingWindow(appUnreadable: false, inSystemList: false, place: .elsewhere))
        #expect(!shouldForgetMissingWindow(appUnreadable: true, inSystemList: true, place: .elsewhere))
    }

    @Test func aClosedWindowIsForgotten() {
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: false, place: .gone))
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .gone) == true)
    }

    @Test func aWindowOfAnAppThatCouldNotBeReadIsKeptWhileTheSystemStillHasIt() {
        #expect(!shouldForgetMissingWindow(appUnreadable: true, inSystemList: true, place: .here))
        #expect(!shouldForgetMissingWindow(appUnreadable: true, inSystemList: true, place: .unknown))
    }

    @Test func aWindowOfAnAppThatCouldNotBeReadIsForgottenWhenTheSystemLostIt() {
        #expect(shouldForgetMissingWindow(appUnreadable: true, inSystemList: false, place: .gone))
    }

    @Test func aHiddenWindowOnTheActiveSpaceIsForgottenAsBefore() {
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .here))
    }

    @Test func withoutThePrivateFunctionsTheOldRuleHolds() {
        #expect(shouldForgetMissingWindow(appUnreadable: false, inSystemList: true, place: .unknown))
    }
}
