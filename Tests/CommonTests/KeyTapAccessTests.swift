import Testing
@testable import Common

@Suite struct KeyTapAccessTests {
    @Test func installsTheTapsWhenThePermissionIsThere() {
        #expect(KeyTapAccess.action(trusted: true, listening: false) == .start)
    }

    @Test func removesTheTapsWhenThePermissionGoesAway() {
        #expect(KeyTapAccess.action(trusted: false, listening: true) == .stop)
    }

    @Test func changesNothingOtherwise() {
        #expect(KeyTapAccess.action(trusted: true, listening: true) == .keep)
        #expect(KeyTapAccess.action(trusted: false, listening: false) == .keep)
    }
}
